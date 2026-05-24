package com.example.ebookreader.service.impl;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.dto.AudioTrackDTO;
import com.example.ebookreader.dto.BookPageResponse;
import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.model.AudioTrack;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.model.Genre;
import com.example.ebookreader.repository.AudioTrackRepository;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.repository.ChapterRepository;
import com.example.ebookreader.service.BookCanonicalizationService;
import jakarta.persistence.criteria.Join;
import jakarta.persistence.criteria.JoinType;
import jakarta.persistence.criteria.Predicate;
import com.example.ebookreader.service.BookService;

@Service
public class BookServiceImpl implements BookService {

    private final BookRepository bookRepository;
    private final ChapterRepository chapterRepository;
    private final AudioTrackRepository audioTrackRepository;
    private final BookCanonicalizationService canonicalizationService;

    @Autowired
    public BookServiceImpl(
            BookRepository bookRepository,
            ChapterRepository chapterRepository,
            AudioTrackRepository audioTrackRepository,
            BookCanonicalizationService canonicalizationService) {
        this.bookRepository = bookRepository;
        this.chapterRepository = chapterRepository;
        this.audioTrackRepository = audioTrackRepository;
        this.canonicalizationService = canonicalizationService;
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> getAllBooks() {
        return canonicalizationService.canonicalizeBooks(bookRepository.findAll());
    }

    @Override
    @Transactional(readOnly = true)
    public BookPageResponse getBooksPage(
            int page,
            int size,
            String query,
            List<String> languages,
            List<String> genres,
            Double minRating,
            List<String> contentFeatures,
            BookAvailability availability,
            String sort) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.max(1, Math.min(size, 100));
        Pageable pageable = PageRequest.of(safePage, safeSize, sortFor(sort));
        Page<Book> result = bookRepository.findAll(
                buildSpecification(query, languages, genres, minRating, contentFeatures, availability),
                pageable
        );
        return new BookPageResponse(
                canonicalizationService.canonicalizeBooks(result.getContent()),
                result.getNumber(),
                result.getSize(),
                result.getTotalElements(),
                result.getTotalPages(),
                result.hasNext()
        );
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> getLibraryBooks() {
        return canonicalizationService.canonicalizeBooks(bookRepository.findByAvailabilityIn(
                List.of(BookAvailability.TEXT, BookAvailability.AUDIO, BookAvailability.SYNCED)));
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> searchBooks(String query) {
        if (query == null || query.trim().isEmpty()) {
            return canonicalizationService.canonicalizeBooks(bookRepository.findAll());
        }
        return canonicalizationService.canonicalizeBooks(bookRepository.findAll().stream()
                .filter(book -> 
                    safeLower(book.getTitle()).contains(query.toLowerCase()) ||
                    safeLower(book.getAuthor()).contains(query.toLowerCase()))
                .collect(Collectors.toList()));
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<Book> getBookById(Long id) {
        return canonicalizationService.findCanonicalById(id);
    }

    @Override
    @Transactional(readOnly = true)
    public List<ChapterDTO> getBookChapters(Long bookId) {
        List<Chapter> chapters = chapterRepository.findByBookIdOrderByChapterOrderAsc(bookId);
        return chapters.stream()
                .map(ch -> new ChapterDTO(
                        ch.getId(),
                        ch.getChapterOrder(),
                        ch.getTitle(),
                        null // Не отдаём контент в списке глав
                ))
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<ChapterDTO> getChapter(Long bookId, int chapterOrder) {
        return chapterRepository.findByBookIdAndChapterOrder(bookId, chapterOrder)
                .map(ch -> new ChapterDTO(
                        ch.getId(),
                        ch.getChapterOrder(),
                        ch.getTitle(),
                        ch.getContent()
                ));
    }

    @Override
    @Transactional(readOnly = true)
    public List<AudioTrackDTO> getAudioTracks(Long bookId) {
        return audioTrackRepository.findByBookIdOrderBySegmentOrderAsc(bookId).stream()
                .map(track -> toAudioTrackDto(bookId, track))
                .collect(Collectors.toList());
    }

    private AudioTrackDTO toAudioTrackDto(Long bookId, AudioTrack track) {
        String streamUrl = "/api/books/" + bookId + "/audio-tracks/" + track.getId() + "/stream";
        return new AudioTrackDTO(
                track.getId(),
                track.getSegmentOrder(),
                track.getTitle(),
                track.getDurationMs(),
                streamUrl,
                track.getContentType()
        );
    }

    private String safeLower(String value) {
        return value == null ? "" : value.toLowerCase();
    }

    private Specification<Book> buildSpecification(
            String query,
            List<String> languages,
            List<String> genres,
            Double minRating,
            List<String> contentFeatures,
            BookAvailability availability) {
        return (root, criteriaQuery, builder) -> {
            List<Predicate> predicates = new java.util.ArrayList<>();
            if (criteriaQuery != null) {
                criteriaQuery.distinct(true);
            }

            String normalizedQuery = query == null ? "" : query.trim().toLowerCase();
            if (!normalizedQuery.isEmpty()) {
                String like = "%" + normalizedQuery + "%";
                predicates.add(builder.or(
                        builder.like(builder.lower(root.get("title")), like),
                        builder.like(builder.lower(root.get("author")), like),
                        builder.like(builder.lower(root.get("description")), like)
                ));
            }

            List<String> normalizedLanguages = normalizeFilterValues(languages);
            if (!normalizedLanguages.isEmpty()) {
                predicates.add(builder.lower(root.get("languageCode")).in(normalizedLanguages));
            }

            List<String> normalizedGenres = normalizeRawValues(genres);
            if (!normalizedGenres.isEmpty()) {
                Join<Book, Genre> genreJoin = root.join("genres", JoinType.LEFT);
                predicates.add(builder.lower(genreJoin.get("name")).in(normalizedGenres));
            }

            if (minRating != null) {
                predicates.add(builder.greaterThanOrEqualTo(root.get("averageRating"), minRating));
            }

            List<String> normalizedFeatures = normalizeRawValues(contentFeatures);
            if (normalizedFeatures.contains("text") || normalizedFeatures.contains("readable")) {
                predicates.add(root.get("availability").in(BookAvailability.TEXT, BookAvailability.SYNCED));
            }
            if (normalizedFeatures.contains("audio") || normalizedFeatures.contains("listenable")) {
                predicates.add(root.get("availability").in(BookAvailability.AUDIO, BookAvailability.SYNCED));
            }

            if (availability != null) {
                predicates.add(builder.equal(root.get("availability"), availability));
            }

            return builder.and(predicates.toArray(Predicate[]::new));
        };
    }

    private List<String> normalizeFilterValues(List<String> values) {
        if (values == null) {
            return List.of();
        }
        return values.stream()
                .filter(value -> value != null && !value.isBlank())
                .map(value -> value.trim().toLowerCase())
                .map(this::normalizeLanguageAlias)
                .distinct()
                .toList();
    }

    private List<String> normalizeRawValues(List<String> values) {
        if (values == null) {
            return List.of();
        }
        return values.stream()
                .filter(value -> value != null && !value.isBlank())
                .map(value -> value.trim().toLowerCase())
                .distinct()
                .toList();
    }

    private String normalizeLanguageAlias(String value) {
        return switch (value) {
            case "en", "english" -> "eng";
            case "es", "spanish", "español" -> "spa";
            case "ar", "arabic", "العربية" -> "ara";
            case "pt", "portuguese", "português" -> "por";
            case "ru", "russian", "русский" -> "rus";
            case "kk", "kazakh", "қазақша", "kaz" -> "kaz";
            default -> value;
        };
    }

    private Sort sortFor(String value) {
        String normalized = value == null ? "popular" : value.trim().toLowerCase();
        return switch (normalized) {
            case "title", "title_asc" -> Sort.by(Sort.Order.asc("title").ignoreCase());
            case "title_desc" -> Sort.by(Sort.Order.desc("title").ignoreCase());
            case "rating", "rating_desc" -> Sort.by(Sort.Order.desc("averageRating").nullsLast(), Sort.Order.desc("ratingsCount").nullsLast());
            case "rating_asc" -> Sort.by(Sort.Order.asc("averageRating").nullsLast());
            case "language", "language_asc" -> Sort.by(Sort.Order.asc("languageCode").nullsLast(), Sort.Order.asc("title").ignoreCase());
            case "language_desc" -> Sort.by(Sort.Order.desc("languageCode").nullsLast(), Sort.Order.asc("title").ignoreCase());
            case "popular", "popularity", "popularity_desc", "recommended" -> Sort.by(Sort.Order.desc("ratingsCount").nullsLast(), Sort.Order.desc("averageRating").nullsLast());
            case "popularity_asc" -> Sort.by(Sort.Order.asc("ratingsCount").nullsLast(), Sort.Order.asc("averageRating").nullsLast());
            default -> Sort.by(Sort.Order.desc("ratingsCount").nullsLast(), Sort.Order.asc("title").ignoreCase());
        };
    }
}
