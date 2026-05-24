package com.example.ebookreader.service;

import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.regex.Pattern;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.repository.BookRepository;

@Service
public class BookCanonicalizationService {

    private static final Pattern DIACRITICS = Pattern.compile("\\p{M}+");
    private static final Pattern NON_ALNUM = Pattern.compile("[^a-z0-9]+");

    private final BookRepository bookRepository;
    private volatile CanonicalIndex cachedIndex;

    public BookCanonicalizationService(BookRepository bookRepository) {
        this.bookRepository = bookRepository;
    }

    @Transactional(readOnly = true)
    public Optional<Book> findCanonicalById(Long bookId) {
        if (bookId == null) {
            return Optional.empty();
        }
        Long canonicalId = index().canonicalIdByBookId().getOrDefault(bookId, bookId);
        return bookRepository.findById(canonicalId);
    }

    @Transactional(readOnly = true)
    public Book canonicalize(Book book) {
        if (book == null || book.getId() == null) {
            return book;
        }
        Long canonicalId = index().canonicalIdByBookId().get(book.getId());
        if (canonicalId == null || canonicalId.equals(book.getId())) {
            return book;
        }
        return bookRepository.findById(canonicalId).orElse(book);
    }

    @Transactional(readOnly = true)
    public List<Book> canonicalizeBooks(Collection<Book> books) {
        if (books == null || books.isEmpty()) {
            return List.of();
        }

        CanonicalIndex index = index();
        List<Long> orderedCanonicalIds = books.stream()
                .filter(Objects::nonNull)
                .map(Book::getId)
                .filter(Objects::nonNull)
                .map(bookId -> index.canonicalIdByBookId().getOrDefault(bookId, bookId))
                .distinct()
                .toList();

        Map<Long, Book> booksById = new HashMap<>();
        for (Book book : bookRepository.findAllById(orderedCanonicalIds)) {
            booksById.put(book.getId(), book);
        }

        List<Book> result = new ArrayList<>();
        for (Long canonicalId : orderedCanonicalIds) {
            Book book = booksById.get(canonicalId);
            if (book != null) {
                result.add(book);
            }
        }
        return result;
    }

    @Transactional(readOnly = true)
    public Map<String, Book> canonicalBooksByGoodreadsId(Collection<String> goodreadsIds) {
        if (goodreadsIds == null || goodreadsIds.isEmpty()) {
            return Map.of();
        }

        CanonicalIndex index = index();
        Map<String, Long> canonicalIdByGoodreadsId = new LinkedHashMap<>();
        for (String goodreadsId : goodreadsIds) {
            if (goodreadsId == null || goodreadsId.isBlank()) {
                continue;
            }
            Long canonicalId = index.canonicalIdByGoodreadsId().get(goodreadsId);
            if (canonicalId != null) {
                canonicalIdByGoodreadsId.put(goodreadsId, canonicalId);
            }
        }

        Map<Long, Book> booksById = new HashMap<>();
        for (Book book : bookRepository.findAllById(canonicalIdByGoodreadsId.values())) {
            booksById.put(book.getId(), book);
        }

        Map<String, Book> result = new HashMap<>();
        for (Map.Entry<String, Long> entry : canonicalIdByGoodreadsId.entrySet()) {
            Book book = booksById.get(entry.getValue());
            if (book != null) {
                result.put(entry.getKey(), book);
            }
        }
        return result;
    }

    public void reload() {
        cachedIndex = null;
    }

    private CanonicalIndex index() {
        CanonicalIndex index = cachedIndex;
        if (index != null) {
            return index;
        }
        synchronized (this) {
            if (cachedIndex == null) {
                cachedIndex = buildIndex();
            }
            return cachedIndex;
        }
    }

    private CanonicalIndex buildIndex() {
        Map<String, Book> canonicalByKey = new HashMap<>();
        Map<Long, String> keyByBookId = new HashMap<>();
        List<Book> books = bookRepository.findAll();

        for (Book book : books) {
            String key = canonicalKey(book);
            if (key.isBlank()) {
                continue;
            }
            keyByBookId.put(book.getId(), key);
            Book current = canonicalByKey.get(key);
            if (current == null || canonicalScore(book) > canonicalScore(current)) {
                canonicalByKey.put(key, book);
            }
        }

        Map<Long, Long> canonicalIdByBookId = new HashMap<>();
        Map<String, Long> canonicalIdByGoodreadsId = new HashMap<>();
        for (Book book : books) {
            String key = keyByBookId.get(book.getId());
            Book canonical = key == null ? null : canonicalByKey.get(key);
            Long canonicalId = canonical == null ? book.getId() : canonical.getId();
            canonicalIdByBookId.put(book.getId(), canonicalId);
            if (book.getGoodreadsId() != null && !book.getGoodreadsId().isBlank()) {
                canonicalIdByGoodreadsId.put(book.getGoodreadsId(), canonicalId);
            }
        }

        return new CanonicalIndex(canonicalIdByBookId, canonicalIdByGoodreadsId);
    }

    private String canonicalKey(Book book) {
        String title = normalizeText(book.getTitle());
        String author = normalizeText(primaryAuthor(book.getAuthor()));
        String language = normalizeText(book.getLanguageCode());
        if (title.isBlank() || author.isBlank()) {
            return "";
        }
        return title + "|" + author + "|" + language;
    }

    private String primaryAuthor(String author) {
        if (author == null) {
            return "";
        }
        return author.split("[,|/]", 2)[0].trim();
    }

    private String normalizeText(String raw) {
        if (raw == null) {
            return "";
        }
        String normalized = Normalizer.normalize(raw.toLowerCase(Locale.ROOT), Normalizer.Form.NFD);
        normalized = DIACRITICS.matcher(normalized).replaceAll("");
        return NON_ALNUM.matcher(normalized).replaceAll(" ").trim();
    }

    private long canonicalScore(Book book) {
        long score = 0;
        BookAvailability availability = book.getAvailability();
        if (availability == BookAvailability.SYNCED) {
            score += 1_000_000_000L;
        } else if (availability == BookAvailability.TEXT || availability == BookAvailability.AUDIO) {
            score += 500_000_000L;
        }
        if (book.getRatingsCount() != null) {
            score += book.getRatingsCount();
        }
        if (book.getPageCount() != null && book.getPageCount() > 20) {
            score += 100_000L + book.getPageCount();
        }
        if (book.getCoverUrl() != null && !book.getCoverUrl().isBlank()) {
            score += 10_000L;
        }
        if (book.getDescription() != null && !book.getDescription().isBlank()) {
            score += Math.min(book.getDescription().length(), 2_000);
        }
        return score;
    }

    private record CanonicalIndex(
            Map<Long, Long> canonicalIdByBookId,
            Map<String, Long> canonicalIdByGoodreadsId) {
    }
}
