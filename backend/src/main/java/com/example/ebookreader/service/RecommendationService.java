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
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.ReadingStatus;
import com.example.ebookreader.model.User;
import com.example.ebookreader.model.UserBook;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.repository.UserBookRepository;

@Service
public class RecommendationService {

    private final BookRepository bookRepository;
    private final UserBookRepository userBookRepository;
    private final Path similarityPath;
    private Map<String, List<ItemNeighbor>> neighborsByGoodreadsId;

    public RecommendationService(
            BookRepository bookRepository,
            UserBookRepository userBookRepository,
            @Value("${recommendations.item-similarity-path:../data/recommendations/item_cf_similar.csv}") String similarityPath) {
        this.bookRepository = bookRepository;
        this.userBookRepository = userBookRepository;
        this.similarityPath = Path.of(similarityPath);
    }

    public List<Map<String, Object>> recommendForUser(User user, int limit) {
        List<UserBook> history = userBookRepository.findByUserId(user.getId());
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

        return materializeResults(scores.values(), limit);
    }

    public List<Map<String, Object>> findSimilarBooks(Long bookId, int limit) {
        Optional<Book> book = bookRepository.findById(bookId);
        if (book.isEmpty() || book.get().getGoodreadsId() == null || book.get().getGoodreadsId().isBlank()) {
            return List.of();
        }

        List<ItemNeighbor> neighbors = getNeighborsByGoodreadsId()
                .getOrDefault(book.get().getGoodreadsId(), List.of());
        Map<String, CandidateScore> scores = new LinkedHashMap<>();
        for (ItemNeighbor neighbor : neighbors) {
            CandidateScore score = scores.computeIfAbsent(neighbor.similarGoodreadsId(), CandidateScore::new);
            score.add(neighbor.score(), neighbor.coLikes());
        }
        return materializeResults(scores.values(), limit);
    }

    public synchronized void reload() {
        neighborsByGoodreadsId = null;
        getNeighborsByGoodreadsId();
    }

    private Map<String, Double> buildSourceWeights(List<UserBook> history) {
        Map<String, Double> weights = new HashMap<>();
        for (UserBook userBook : history) {
            Book book = userBook.getBook();
            if (book == null || book.getGoodreadsId() == null || book.getGoodreadsId().isBlank()) {
                continue;
            }

            double weight = 0.0;
            Integer rating = userBook.getRating();
            if (rating != null) {
                if (rating >= 4) {
                    weight = rating - 3.0;
                }
            } else if (userBook.getStatus() == ReadingStatus.FINISHED) {
                weight = 1.0;
            } else if (userBook.getStatus() == ReadingStatus.READING) {
                weight = 0.7;
            } else if (userBook.isBookmarked()) {
                weight = 0.4;
            }

            if (weight > 0) {
                weights.put(book.getGoodreadsId(), weight);
            }
        }
        return weights;
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

    private List<Map<String, Object>> materializeResults(Collection<CandidateScore> candidateScores, int limit) {
        List<CandidateScore> ranked = candidateScores.stream()
                .sorted(Comparator
                        .comparingDouble(CandidateScore::score).reversed()
                        .thenComparing(Comparator.comparingInt(CandidateScore::evidenceBooks).reversed()))
                .limit(limit)
                .toList();

        List<String> goodreadsIds = ranked.stream()
                .map(CandidateScore::goodreadsId)
                .toList();
        Map<String, Book> booksByGoodreadsId = new HashMap<>();
        for (Book book : bookRepository.findByGoodreadsIdIn(goodreadsIds)) {
            booksByGoodreadsId.put(book.getGoodreadsId(), book);
        }

        List<Map<String, Object>> results = new ArrayList<>();
        for (CandidateScore candidate : ranked) {
            Book book = booksByGoodreadsId.get(candidate.goodreadsId());
            if (book == null) {
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
