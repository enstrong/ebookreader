package com.example.ebookreader.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.ReadingStatus;
import com.example.ebookreader.model.User;
import com.example.ebookreader.model.UserBook;
import com.example.ebookreader.repository.UserBookRepository;

@Service
public class RecommendationService {

    private final UserBookRepository userBookRepository;
    private final BookCanonicalizationService canonicalizationService;
    private final GoodreadsWorkService goodreadsWorkService;
    private final Path similarityPath;
    private final RestTemplate restTemplate;
    private final String hybridServiceUrl;
    private Map<String, List<ItemNeighbor>> neighborsByGoodreadsId;

    public RecommendationService(
            UserBookRepository userBookRepository,
            BookCanonicalizationService canonicalizationService,
            GoodreadsWorkService goodreadsWorkService,
            @Value("${recommendations.item-similarity-path:../data/recommendations/item_cf_similar.csv}") String similarityPath,
            @Value("${recommendations.hybrid-service-url:http://127.0.0.1:8001}") String hybridServiceUrl,
            @Value("${recommendations.hybrid-timeout-ms:8000}") int hybridTimeoutMs) {
        this.userBookRepository = userBookRepository;
        this.canonicalizationService = canonicalizationService;
        this.goodreadsWorkService = goodreadsWorkService;
        this.similarityPath = Path.of(similarityPath);
        this.hybridServiceUrl = hybridServiceUrl.replaceAll("/+$", "");
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(hybridTimeoutMs);
        requestFactory.setReadTimeout(hybridTimeoutMs);
        this.restTemplate = new RestTemplate(requestFactory);
    }

    public List<Map<String, Object>> recommendForUser(User user, int limit) {
        List<UserBook> history = userBookRepository.findByUserIdWithBook(user.getId());
        LanguagePreference languagePreference = languagePreference(history);
        Optional<List<Map<String, Object>>> hybrid = recommendWithHybrid(history, limit, languagePreference);
        if (hybrid.isPresent()) {
            return hybrid.get();
        }
        Map<String, Double> sourceWeights = buildSourceWeights(history);
        Set<String> alreadyInteracted = collectInteractedGoodreadsIds(history);

        if (sourceWeights.isEmpty()) {
            return List.of();
        }

        Map<String, CandidateScore> scores = new HashMap<>();
        Map<String, List<ItemNeighbor>> neighbors = getNeighborsByGoodreadsId();
        for (Map.Entry<String, Double> source : sourceWeights.entrySet()) {
            for (ItemNeighbor neighbor : neighbors.getOrDefault(source.getKey(), List.of())) {
                if (alreadyInteracted.contains(neighbor.similarGoodreadsId())) {
                    continue;
                }
                CandidateScore score = scores.computeIfAbsent(neighbor.similarGoodreadsId(), CandidateScore::new);
                score.add(neighbor.score() * source.getValue(), neighbor.coLikes());
            }
        }

        return materializeResults(scores.values(), limit, languagePreference);
    }

    public List<Map<String, Object>> findSimilarBooks(Long bookId, int limit) {
        Optional<Book> book = canonicalizationService.findCanonicalById(bookId);
        if (book.isEmpty() || book.get().getGoodreadsId() == null || book.get().getGoodreadsId().isBlank()) {
            return List.of();
        }
        Optional<List<Map<String, Object>>> hybrid = similarWithHybrid(book.get(), limit);
        if (hybrid.isPresent()) {
            return hybrid.get();
        }

        List<ItemNeighbor> neighbors = getNeighborsByGoodreadsId()
                .getOrDefault(book.get().getGoodreadsId(), List.of());
        Map<String, CandidateScore> scores = new LinkedHashMap<>();
        for (ItemNeighbor neighbor : neighbors) {
            CandidateScore score = scores.computeIfAbsent(neighbor.similarGoodreadsId(), CandidateScore::new);
            score.add(neighbor.score(), neighbor.coLikes());
        }
        return materializeResults(scores.values(), limit, languagePreferenceForBook(book.get()));
    }

    public List<Map<String, Object>> previewRecommendations(List<Map<String, Object>> selectedBooks, int limit) {
        Optional<List<Map<String, Object>>> hybrid = previewWithHybrid(selectedBooks, limit);
        if (hybrid.isPresent()) {
            return hybrid.get();
        }

        Map<String, CandidateScore> scores = new HashMap<>();
        Map<String, List<ItemNeighbor>> neighbors = getNeighborsByGoodreadsId();
        for (Map<String, Object> selected : selectedBooks) {
            String goodreadsId = selected.get("goodreadsBookId") == null ? null : selected.get("goodreadsBookId").toString();
            if (goodreadsId == null || goodreadsId.isBlank()) {
                continue;
            }
            double rating = readDouble(selected.get("rating"), 5.0);
            for (ItemNeighbor neighbor : neighbors.getOrDefault(goodreadsId, List.of())) {
                CandidateScore score = scores.computeIfAbsent(neighbor.similarGoodreadsId(), CandidateScore::new);
                score.add(neighbor.score() * Math.max(1.0, rating - 3.0), neighbor.coLikes());
            }
        }
        return materializeResults(scores.values(), limit, languagePreferenceFromSelectedBooks(selectedBooks));
    }

    public int positiveSourceCount(User user) {
        return (int) buildSourceWeights(userBookRepository.findByUserIdWithBook(user.getId()))
                .values()
                .stream()
                .filter(weight -> weight > 0)
                .count();
    }

    private Optional<List<Map<String, Object>>> recommendWithHybrid(
            List<UserBook> history,
            int limit,
            LanguagePreference languagePreference) {
        List<Map<String, Object>> interactions = history.stream()
                .map(this::interactionPayload)
                .filter(row -> row.get("goodreadsBookId") != null)
                .toList();
        if (interactions.isEmpty()) {
            return Optional.empty();
        }
        return callHybridList(
                "/recommend",
                Map.of("limit", hybridLookupLimit(limit, languagePreference), "interactions", interactions),
                "recommendations",
                languagePreference,
                limit);
    }

    private Optional<List<Map<String, Object>>> previewWithHybrid(List<Map<String, Object>> selectedBooks, int limit) {
        if (selectedBooks == null || selectedBooks.isEmpty()) {
            return Optional.empty();
        }
        return callHybridList(
                "/preview",
                Map.of(
                        "limit",
                        hybridLookupLimit(limit, languagePreferenceFromSelectedBooks(selectedBooks)),
                        "interactions",
                        selectedBooks),
                "recommendations",
                languagePreferenceFromSelectedBooks(selectedBooks),
                limit);
    }

    private Optional<List<Map<String, Object>>> similarWithHybrid(Book book, int limit) {
        try {
            String url = hybridServiceUrl + "/similar/" + book.getGoodreadsId() + "?limit=" + limit;
            ResponseEntity<Map> response = restTemplate.getForEntity(url, Map.class);
            return materializeHybridResponse(response.getBody(), "similar", languagePreferenceForBook(book), limit);
        } catch (Exception ex) {
            return Optional.empty();
        }
    }

    private Optional<List<Map<String, Object>>> callHybridList(
            String path,
            Map<String, Object> payload,
            String key,
            LanguagePreference languagePreference,
            int limit) {
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            ResponseEntity<Map> response = restTemplate.postForEntity(
                    hybridServiceUrl + path,
                    new HttpEntity<>(payload, headers),
                    Map.class
            );
            return materializeHybridResponse(response.getBody(), key, languagePreference, limit);
        } catch (Exception ex) {
            return Optional.empty();
        }
    }

    private Optional<List<Map<String, Object>>> materializeHybridResponse(
            Map<?, ?> response,
            String key,
            LanguagePreference languagePreference,
            int limit) {
        if (response == null || !(response.get(key) instanceof List<?> rows)) {
            return Optional.empty();
        }

        List<HybridCandidate> ranked = rows.stream()
                .filter(Map.class::isInstance)
                .map(Map.class::cast)
                .map(this::hybridCandidate)
                .filter(Optional::isPresent)
                .map(Optional::get)
                .toList();
        if (ranked.isEmpty()) {
            return Optional.of(List.of());
        }

        Set<String> lookupGoodreadsIds = new HashSet<>();
        for (HybridCandidate candidate : ranked) {
            lookupGoodreadsIds.add(candidate.goodreadsId());
            lookupGoodreadsIds.addAll(goodreadsWorkService.bookIdsForSameWork(candidate.goodreadsId()));
        }
        Map<String, Book> booksByGoodreadsId = canonicalizationService.canonicalBooksByGoodreadsId(lookupGoodreadsIds);

        List<Map<String, Object>> results = new ArrayList<>();
        Set<Long> seenBookIds = new HashSet<>();
        for (HybridCandidate candidate : ranked) {
            Book book = preferredBookForCandidate(candidate.goodreadsId(), booksByGoodreadsId, languagePreference);
            if (book == null || !seenBookIds.add(book.getId())) {
                continue;
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("book", book);
            row.put("score", candidate.score());
            row.put("alsScore", candidate.alsScore());
            row.put("contentScore", candidate.contentScore());
            row.put("reason", candidate.reason());
            row.put("model", "hybrid_als_metadata");
            results.add(row);
            if (results.size() >= limit) {
                break;
            }
        }
        return Optional.of(results);
    }

    private int hybridLookupLimit(int requestedLimit, LanguagePreference languagePreference) {
        if (languagePreference.strict()) {
            return Math.min(500, Math.max(requestedLimit * 10, 100));
        }
        return requestedLimit;
    }

    private Optional<HybridCandidate> hybridCandidate(Map<?, ?> row) {
        Object rawId = row.get("goodreadsBookId");
        if (rawId == null) {
            rawId = row.get("goodreads_book_id");
        }
        if (rawId == null) {
            return Optional.empty();
        }
        String goodreadsId = rawId.toString();
        if (goodreadsId.isBlank()) {
            return Optional.empty();
        }
        return Optional.of(new HybridCandidate(
                goodreadsId,
                readDouble(row.get("score"), 0.0),
                readDouble(row.get("alsScore"), 0.0),
                readDouble(row.get("contentScore"), 0.0),
                row.get("reason") == null ? "Похоже на ваши оценки" : row.get("reason").toString()
        ));
    }

    private Book preferredBookForCandidate(
            String candidateGoodreadsId,
            Map<String, Book> booksByGoodreadsId,
            LanguagePreference languagePreference) {
        if (candidateGoodreadsId == null || candidateGoodreadsId.isBlank()) {
            return null;
        }

        List<String> siblingGoodreadsIds = goodreadsWorkService.bookIdsForSameWork(candidateGoodreadsId);
        if (!languagePreference.languages().isEmpty() && !siblingGoodreadsIds.isEmpty()) {
            for (String preferredLanguage : languagePreference.languages()) {
                Book best = null;
                for (String siblingGoodreadsId : siblingGoodreadsIds) {
                    Book book = booksByGoodreadsId.get(siblingGoodreadsId);
                    if (book == null || !preferredLanguage.equals(normalizeLanguage(book.getLanguageCode()))) {
                        continue;
                    }
                    if (best == null || languageBookScore(book) > languageBookScore(best)) {
                        best = book;
                    }
                }
                if (best != null) {
                    return best;
                }
            }
        }

        if (languagePreference.strict()) {
            return null;
        }
        return booksByGoodreadsId.get(candidateGoodreadsId);
    }

    private LanguagePreference languagePreference(List<UserBook> history) {
        Map<String, Double> scoreByLanguage = new HashMap<>();
        double averageRating = userAverageRating(history);
        for (UserBook userBook : history) {
            Book book = userBook.getBook();
            if (book == null) {
                continue;
            }
            String language = normalizeLanguage(book.getLanguageCode());
            if (language.isBlank()) {
                continue;
            }

            double weight = 0.0;
            Integer rating = userBook.getRating();
            if (rating != null) {
                weight = explicitRatingWeight(rating, averageRating);
            } else if (userBook.getStatus() == ReadingStatus.FINISHED) {
                weight = 1.0;
            } else if (userBook.getStatus() == ReadingStatus.READING) {
                weight = 0.7;
            } else if (userBook.isBookmarked()) {
                weight = 0.4;
            }
            if (weight > 0) {
                scoreByLanguage.merge(language, weight, Double::sum);
            }
        }
        return languagePreference(scoreByLanguage);
    }

    private LanguagePreference languagePreferenceFromSelectedBooks(List<Map<String, Object>> selectedBooks) {
        Map<String, Double> scoreByLanguage = new HashMap<>();
        if (selectedBooks == null) {
            return new LanguagePreference(List.of(), false);
        }
        for (Map<String, Object> selectedBook : selectedBooks) {
            String language = normalizeLanguage(selectedBook.get("language") == null ? null : selectedBook.get("language").toString());
            if (language.isBlank()) {
                continue;
            }
            double rating = readDouble(selectedBook.get("rating"), 5.0);
            if (rating >= 4) {
                scoreByLanguage.merge(language, Math.max(1.0, rating - 3.0), Double::sum);
            }
        }
        return languagePreference(scoreByLanguage);
    }

    private LanguagePreference languagePreferenceForBook(Book book) {
        String language = book == null ? "" : normalizeLanguage(book.getLanguageCode());
        return language.isBlank() ? new LanguagePreference(List.of(), false) : new LanguagePreference(List.of(language), true);
    }

    private LanguagePreference languagePreference(Map<String, Double> scoreByLanguage) {
        double total = scoreByLanguage.values().stream().mapToDouble(Double::doubleValue).sum();
        List<Map.Entry<String, Double>> ranked = scoreByLanguage.entrySet().stream()
                .filter(entry -> entry.getValue() > 0)
                .sorted(Map.Entry.<String, Double>comparingByValue().reversed())
                .toList();
        List<String> languages = ranked.stream().map(Map.Entry::getKey).toList();
        boolean strict = !ranked.isEmpty() && total > 0 && ranked.get(0).getValue() / total >= 0.80;
        return new LanguagePreference(languages, strict);
    }

    private String normalizeLanguage(String rawLanguage) {
        if (rawLanguage == null) {
            return "";
        }
        String language = rawLanguage.trim().toLowerCase(Locale.ROOT);
        if (language.isBlank()) {
            return "";
        }
        if (language.equals("ru") || language.equals("rus") || language.equals("russian")) {
            return "rus";
        }
        if (language.equals("en")
                || language.equals("eng")
                || language.startsWith("en-")
                || language.equals("english")) {
            return "eng";
        }
        return language;
    }

    private long languageBookScore(Book book) {
        long score = 0L;
        if (book.getRatingsCount() != null) {
            score += book.getRatingsCount();
        }
        if (book.getCoverUrl() != null && !book.getCoverUrl().isBlank()) {
            score += 10_000L;
        }
        if (book.getDescription() != null && !book.getDescription().isBlank()) {
            score += Math.min(book.getDescription().length(), 2_000);
        }
        return score;
    }

    private Map<String, Object> interactionPayload(UserBook userBook) {
        Map<String, Object> row = new LinkedHashMap<>();
        Book book = userBook.getBook();
        if (book == null || book.getGoodreadsId() == null || book.getGoodreadsId().isBlank()) {
            row.put("goodreadsBookId", null);
            return row;
        }
        row.put("goodreadsBookId", book.getGoodreadsId());
        row.put("goodreads_book_id", book.getGoodreadsId());
        row.put("goodreadsId", book.getGoodreadsId());
        row.put("language", book.getLanguageCode());
        row.put("rating", userBook.getRating() == null ? 0 : userBook.getRating());
        row.put("status", userBook.getStatus() == null ? null : userBook.getStatus().name());
        row.put("bookmarked", userBook.isBookmarked());
        return row;
    }

    public synchronized void reload() {
        neighborsByGoodreadsId = null;
        goodreadsWorkService.reload();
        getNeighborsByGoodreadsId();
    }

    private Map<String, Double> buildSourceWeights(List<UserBook> history) {
        Map<String, Double> weights = new HashMap<>();
        double averageRating = userAverageRating(history);
        for (UserBook userBook : history) {
            Book book = userBook.getBook();
            if (book == null || book.getGoodreadsId() == null || book.getGoodreadsId().isBlank()) {
                continue;
            }

            double weight = 0.0;
            Integer rating = userBook.getRating();
            if (rating != null) {
                weight = explicitRatingWeight(rating, averageRating);
            } else if (userBook.getStatus() == ReadingStatus.FINISHED) {
                weight = 1.0;
            } else if (userBook.getStatus() == ReadingStatus.READING) {
                weight = 0.7;
            } else if (userBook.isBookmarked()) {
                weight = 0.4;
            }

            if (weight != 0) {
                weights.put(book.getGoodreadsId(), weight);
            }
        }
        return weights;
    }

    private double explicitRatingWeight(int rating, double averageRating) {
        double centered = averageRating > 0 ? rating - averageRating : rating;
        if (rating >= 4) {
            return Math.max(centered, 1.0 + (rating - 3.0));
        }
        return Math.max(centered, 0.0);
    }

    private double userAverageRating(List<UserBook> history) {
        return history.stream()
                .map(UserBook::getRating)
                .filter(rating -> rating != null && rating > 0)
                .mapToInt(Integer::intValue)
                .average()
                .orElse(0.0);
    }

    private double readDouble(Object value, double fallback) {
        if (value == null) {
            return fallback;
        }
        if (value instanceof Number number) {
            return number.doubleValue();
        }
        try {
            return Double.parseDouble(value.toString());
        } catch (NumberFormatException ex) {
            return fallback;
        }
    }

    private Set<String> collectInteractedGoodreadsIds(List<UserBook> history) {
        Set<String> ids = new HashSet<>();
        for (UserBook userBook : history) {
            Book book = userBook.getBook();
            if (book != null && book.getGoodreadsId() != null && !book.getGoodreadsId().isBlank()) {
                ids.add(book.getGoodreadsId());
            }
        }
        return ids;
    }

    private List<Map<String, Object>> materializeResults(
            Collection<CandidateScore> candidateScores,
            int limit,
            LanguagePreference languagePreference) {
        List<CandidateScore> ranked = candidateScores.stream()
                .filter(candidate -> candidate.score() > 0)
                .sorted(Comparator
                        .comparingDouble(CandidateScore::score).reversed()
                        .thenComparing(Comparator.comparingInt(CandidateScore::evidenceBooks).reversed()))
                .limit(limit)
                .toList();

        Set<String> lookupGoodreadsIds = new HashSet<>();
        for (CandidateScore candidate : ranked) {
            lookupGoodreadsIds.add(candidate.goodreadsId());
            lookupGoodreadsIds.addAll(goodreadsWorkService.bookIdsForSameWork(candidate.goodreadsId()));
        }
        Map<String, Book> booksByGoodreadsId = canonicalizationService.canonicalBooksByGoodreadsId(lookupGoodreadsIds);

        List<Map<String, Object>> results = new ArrayList<>();
        Set<Long> seenBookIds = new HashSet<>();
        for (CandidateScore candidate : ranked) {
            Book book = preferredBookForCandidate(candidate.goodreadsId(), booksByGoodreadsId, languagePreference);
            if (book == null || !seenBookIds.add(book.getId())) {
                continue;
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("book", book);
            row.put("score", candidate.score());
            row.put("evidenceBooks", candidate.evidenceBooks());
            row.put("bestCoLikes", candidate.bestCoLikes());
            results.add(row);
        }
        return results;
    }

    private synchronized Map<String, List<ItemNeighbor>> getNeighborsByGoodreadsId() {
        if (neighborsByGoodreadsId != null) {
            return neighborsByGoodreadsId;
        }

        Path path = resolveSimilarityPath();
        Map<String, List<ItemNeighbor>> loaded = new HashMap<>();
        if (!Files.exists(path)) {
            neighborsByGoodreadsId = loaded;
            return neighborsByGoodreadsId;
        }
        try (BufferedReader reader = Files.newBufferedReader(path)) {
            String header = reader.readLine();
            if (header == null) {
                neighborsByGoodreadsId = loaded;
                return neighborsByGoodreadsId;
            }

            String line;
            while ((line = reader.readLine()) != null) {
                String[] parts = line.split(",", -1);
                if (parts.length < 8) {
                    continue;
                }
                String goodreadsId = parts[1];
                String similarGoodreadsId = parts[3];
                if (goodreadsId.isBlank() || similarGoodreadsId.isBlank()) {
                    continue;
                }
                ItemNeighbor neighbor = new ItemNeighbor(
                        similarGoodreadsId,
                        Double.parseDouble(parts[4]),
                        Integer.parseInt(parts[5])
                );
                loaded.computeIfAbsent(goodreadsId, ignored -> new ArrayList<>()).add(neighbor);
            }
        } catch (IOException ex) {
            throw new IllegalStateException("Could not load recommendation similarities from " + path, ex);
        }

        neighborsByGoodreadsId = loaded;
        return neighborsByGoodreadsId;
    }

    private Path resolveSimilarityPath() {
        if (Files.exists(similarityPath)) {
            return similarityPath;
        }
        Path rootRelative = Path.of("data/recommendations/item_cf_similar.csv");
        if (Files.exists(rootRelative)) {
            return rootRelative;
        }
        return similarityPath;
    }

    private record ItemNeighbor(String similarGoodreadsId, double score, int coLikes) {
    }

    private record HybridCandidate(String goodreadsId, double score, double alsScore, double contentScore, String reason) {
    }

    private record LanguagePreference(List<String> languages, boolean strict) {
    }

    private static class CandidateScore {
        private final String goodreadsId;
        private double score;
        private int evidenceBooks;
        private int bestCoLikes;

        CandidateScore(String goodreadsId) {
            this.goodreadsId = goodreadsId;
        }

        void add(double value, int coLikes) {
            score += value;
            evidenceBooks += 1;
            bestCoLikes = Math.max(bestCoLikes, coLikes);
        }

        String goodreadsId() {
            return goodreadsId;
        }

        double score() {
            return score;
        }

        int evidenceBooks() {
            return evidenceBooks;
        }

        int bestCoLikes() {
            return bestCoLikes;
        }
    }
}
