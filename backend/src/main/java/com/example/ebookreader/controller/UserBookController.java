package com.example.ebookreader.controller;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.dto.BookAnnotationDTO;
import com.example.ebookreader.dto.BookAnnotationRequest;
import com.example.ebookreader.dto.LookupRequest;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAnnotation;
import com.example.ebookreader.model.ProgressMode;
import com.example.ebookreader.model.ReadingStatus;
import com.example.ebookreader.model.User;
import com.example.ebookreader.model.UserBook;
import com.example.ebookreader.repository.BookAnnotationRepository;
import com.example.ebookreader.repository.ChapterRepository;
import com.example.ebookreader.repository.UserBookRepository;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.service.BookCanonicalizationService;
import com.example.ebookreader.service.LookupService;

@RestController
@RequestMapping("/api/user/books")
@CrossOrigin(origins = "*")
public class UserBookController {

    @Autowired
    private UserBookRepository userBookRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private ChapterRepository chapterRepository;

    @Autowired
    private BookAnnotationRepository bookAnnotationRepository;

    @Autowired
    private JwtUtil jwtUtil;

    @Autowired
    private LookupService lookupService;

    @Autowired
    private BookCanonicalizationService canonicalizationService;

    private Optional<User> getUserFromToken(String token) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        return userRepository.findByNickname(username);
    }

    private UserBook getOrCreateUserBook(User user, Book book) {
        return userBookRepository.findByUserIdAndBookId(user.getId(), book.getId())
                .orElseGet(() -> {
                    UserBook ub = new UserBook();
                    ub.setUser(user);
                    ub.setBook(book);
                    ub.setCurrentChapter(1);
                    return ub;
                });
    }

    private Optional<Book> findCanonicalBook(Long bookId) {
        return canonicalizationService.findCanonicalById(bookId);
    }

    private void applyStatus(UserBook ub, ReadingStatus status) {
        LocalDateTime now = LocalDateTime.now();
        ub.setStatus(status);
        ub.setLastReadAt(now);
        if (status == ReadingStatus.READING && ub.getStartedAt() == null) {
            ub.setStartedAt(now);
        }
        if (status == ReadingStatus.FINISHED) {
            if (ub.getStartedAt() == null) {
                ub.setStartedAt(now);
            }
            ub.setFinishedAt(now);
        }
    }

    // Добавить в закладки
    @PostMapping("/{bookId}/bookmark")
    public ResponseEntity<?> addBookmark(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        Optional<User> userOpt = userRepository.findByNickname(username);
        Optional<Book> bookOpt = findCanonicalBook(bookId);

        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        User user = userOpt.get();
        Book book = bookOpt.get();

        UserBook ub = getOrCreateUserBook(user, book);
        ub.setBookmarked(true);
        if (ub.getStatus() == ReadingStatus.WANT_TO_READ) {
            ub.setLastReadAt(LocalDateTime.now());
        }
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of("message", "Добавлено в закладки"));
    }

    // Удалить из закладок
    @DeleteMapping("/{bookId}/bookmark")
    public ResponseEntity<?> removeBookmark(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        return userRepository.findByNickname(username)
                .flatMap(user -> findCanonicalBook(bookId)
                        .flatMap(book -> userBookRepository.findByUserIdAndBookId(user.getId(), book.getId())))
                .map(ub -> {
                    ub.setBookmarked(false);
                    userBookRepository.save(ub);
                    return ResponseEntity.ok(Map.of("message", "Удалено из закладок"));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    // Получить все закладки пользователя
    @GetMapping("/bookmarks")
    public ResponseEntity<?> getBookmarks(@RequestHeader("Authorization") String token) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        return userRepository.findByNickname(username)
                .map(user -> {
                    List<UserBook> bookmarks = userBookRepository.findByUserIdAndBookmarkedTrue(user.getId());
                    List<Map<String, Object>> result = bookmarks.stream()
                            .filter(ub -> ub.getBook() != null && canonicalizationService
                                    .findCanonicalById(ub.getBook().getId())
                                    .map(book -> book.getId().equals(ub.getBook().getId()))
                                    .orElse(true))
                            .map(ub -> {
                                Map<String, Object> item = new HashMap<>();
                                item.put("id", ub.getBook().getId());
                                item.put("title", ub.getBook().getTitle());
                                item.put("author", ub.getBook().getAuthor());
                                item.put("coverUrl", ub.getBook().getCoverUrl());
                                item.put("currentChapter", ub.getCurrentChapter());
                                item.put("segmentOrder", ub.getSegmentOrder());
                                item.put("segmentProgress", ub.getSegmentProgress());
                                item.put("audioPositionMs", ub.getAudioPositionMs());
                                item.put("lastMode", ub.getLastMode().name());
                                item.put("availability", ub.getBook().getAvailability().name());
                                return item;
                            })
                            .collect(Collectors.toList());
                    return ResponseEntity.ok(result);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/ratings")
    public ResponseEntity<?> getRatedBooks(@RequestHeader("Authorization") String token) {
        return getUserFromToken(token)
                .map(user -> {
                    List<UserBook> ratedBooks = userBookRepository
                            .findRatedByUserIdOrderByRatingDateDesc(user.getId());
                    double averageRating = userAverageRating(ratedBooks);
                    Set<Long> seenCanonicalBookIds = new HashSet<>();
                    List<Map<String, Object>> result = ratedBooks.stream()
                            .filter(ub -> {
                                Book book = canonicalizationService.canonicalize(ub.getBook());
                                return book == null || book.getId() == null || seenCanonicalBookIds.add(book.getId());
                            })
                            .map(ub -> ratedBookPayload(ub, averageRating))
                            .collect(Collectors.toList());
                    return ResponseEntity.ok(result);
                })
                .orElse(ResponseEntity.notFound().build());
    }

    // Обновить прогресс чтения
    @PutMapping("/{bookId}/progress")
    public ResponseEntity<?> updateProgress(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @RequestBody Map<String, Object> request) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        Integer segmentOrder = readInteger(request, "segmentOrder");
        if (segmentOrder == null) {
            segmentOrder = readInteger(request, "chapter");
        }

        if (segmentOrder == null || segmentOrder < 1) {
            return ResponseEntity.badRequest().body(Map.of("message", "Неверный номер сегмента"));
        }

        Optional<User> userOpt = userRepository.findByNickname(username);
        Optional<Book> bookOpt = findCanonicalBook(bookId);

        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        User user = userOpt.get();
        Book book = bookOpt.get();

        UserBook ub = getOrCreateUserBook(user, book);
        ub.setSegmentOrder(segmentOrder);
        Double segmentProgress = readDouble(request, "segmentProgress");
        if (segmentProgress != null) {
            ub.setSegmentProgress(segmentProgress);
        }
        Long audioPositionMs = readLong(request, "audioPositionMs");
        if (audioPositionMs != null) {
            ub.setAudioPositionMs(audioPositionMs);
        }
        ProgressMode lastMode = readProgressMode(request, "lastMode");
        if (lastMode != null) {
            ub.setLastMode(lastMode);
        }
        ub.setLastReadAt(LocalDateTime.now());
        if (ub.getStatus() == ReadingStatus.WANT_TO_READ) {
            applyStatus(ub, ReadingStatus.READING);
        }
        userBookRepository.save(ub);

        return ResponseEntity.ok(progressPayload(ub, "Прогресс сохранён"));
    }

    @PutMapping("/{bookId}/status")
    public ResponseEntity<?> updateStatus(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @RequestBody Map<String, String> request) {
        String rawStatus = request.get("status");
        if (rawStatus == null || rawStatus.isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Статус обязателен"));
        }

        ReadingStatus status;
        try {
            status = ReadingStatus.valueOf(rawStatus.trim().toUpperCase());
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("message", "Неверный статус"));
        }

        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        UserBook ub = getOrCreateUserBook(userOpt.get(), bookOpt.get());
        applyStatus(ub, status);
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of(
                "message", "Статус сохранён",
                "status", ub.getStatus().name()
        ));
    }

    @PostMapping("/{bookId}/finish")
    public ResponseEntity<?> finishBook(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        UserBook ub = getOrCreateUserBook(userOpt.get(), bookOpt.get());
        applyStatus(ub, ReadingStatus.FINISHED);
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of(
                "message", "Книга отмечена как прочитанная",
                "status", ub.getStatus().name()
        ));
    }

    @PutMapping("/{bookId}/rating")
    public ResponseEntity<?> updateRating(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @RequestBody Map<String, Integer> request) {
        Integer rating = request.get("rating");
        if (rating == null || rating < 0 || rating > 5) {
            return ResponseEntity.badRequest().body(Map.of("message", "Оценка должна быть от 0 до 5"));
        }

        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        UserBook ub = getOrCreateUserBook(userOpt.get(), bookOpt.get());
        LocalDateTime now = LocalDateTime.now();
        if (rating == 0) {
            ub.setRating(null);
            ub.setRatedAt(null);
        } else {
            ub.setRating(rating);
            ub.setRatedAt(now);
        }
        ub.setLastReadAt(now);
        if (ub.getStatus() == ReadingStatus.WANT_TO_READ) {
            applyStatus(ub, ReadingStatus.FINISHED);
        }
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of(
                "message", "Оценка сохранена",
                "rating", ub.getRating() == null ? 0 : ub.getRating()
        ));
    }

    @DeleteMapping("/{bookId}/rating")
    public ResponseEntity<?> clearRating(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        UserBook ub = getOrCreateUserBook(userOpt.get(), bookOpt.get());
        ub.setRating(null);
        ub.setRatedAt(null);
        ub.setLastReadAt(LocalDateTime.now());
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of(
                "message", "Оценка удалена",
                "rating", 0
        ));
    }

    // Получить прогресс чтения книги
    @GetMapping("/{bookId}/progress")
    public ResponseEntity<?> getProgress(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        return userRepository.findByNickname(username)
                .flatMap(user -> findCanonicalBook(bookId)
                        .flatMap(book -> userBookRepository.findByUserIdAndBookId(user.getId(), book.getId())))
                .map(ub -> {
                    Map<String, Object> result = new HashMap<>();
                    result.put("currentChapter", ub.getCurrentChapter());
                    result.put("segmentOrder", ub.getSegmentOrder());
                    result.put("segmentProgress", ub.getSegmentProgress());
                    result.put("audioPositionMs", ub.getAudioPositionMs());
                    result.put("lastMode", ub.getLastMode().name());
                    result.put("isBookmarked", ub.isBookmarked());
                    result.put("status", ub.getStatus().name());
                    result.put("rating", ub.getRating());
                    result.put("ratedAt", ub.getRatedAt());
                    result.put("startedAt", ub.getStartedAt());
                    result.put("finishedAt", ub.getFinishedAt());
                    result.put("lastReadAt", ub.getLastReadAt());
                    return ResponseEntity.ok(result);
                })
                .orElse(ResponseEntity.ok(Map.of(
                    "currentChapter", 1,
                    "segmentOrder", 1,
                    "segmentProgress", 0.0,
                    "audioPositionMs", 0,
                    "lastMode", ProgressMode.TEXT.name(),
                    "isBookmarked", false,
                    "status", ReadingStatus.WANT_TO_READ.name(),
                    "rating", 0
                )));
    }

    @GetMapping("/{bookId}/annotations")
    public ResponseEntity<?> getBookAnnotations(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        List<BookAnnotationDTO> annotations = bookAnnotationRepository
                .findByUserIdAndBookIdOrderByChapterOrderAscStartOffsetAsc(userOpt.get().getId(), bookOpt.get().getId())
                .stream()
                .map(BookAnnotationDTO::fromEntity)
                .collect(Collectors.toList());
        return ResponseEntity.ok(annotations);
    }

    @PostMapping("/lookup/selection")
    public ResponseEntity<?> lookupSelection(
            @RequestHeader("Authorization") String token,
            @RequestBody LookupRequest request) {
        String text = request.getText() == null ? "" : request.getText().trim();
        if (text.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Текст обязателен"));
        }
        if (text.length() > 500) {
            return ResponseEntity.badRequest().body(Map.of("message", "Выделение слишком длинное"));
        }
        return ResponseEntity.ok(lookupService.lookup(request));
    }

    @GetMapping("/{bookId}/chapters/{chapterOrder}/annotations")
    public ResponseEntity<?> getChapterAnnotations(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Integer chapterOrder) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        List<BookAnnotationDTO> annotations = bookAnnotationRepository
                .findByUserIdAndBookIdAndChapterOrderOrderByStartOffsetAsc(
                        userOpt.get().getId(),
                        bookOpt.get().getId(),
                        chapterOrder)
                .stream()
                .map(BookAnnotationDTO::fromEntity)
                .collect(Collectors.toList());
        return ResponseEntity.ok(annotations);
    }

    @PostMapping("/{bookId}/annotations")
    public ResponseEntity<?> createAnnotation(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @RequestBody BookAnnotationRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        String validationError = validateAnnotationRequest(bookOpt.get().getId(), request, true);
        if (!validationError.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", validationError));
        }

        BookAnnotation annotation = new BookAnnotation();
        annotation.setUser(userOpt.get());
        annotation.setBook(bookOpt.get());
        annotation.setChapterOrder(request.getChapterOrder());
        annotation.setStartOffset(request.getStartOffset());
        annotation.setEndOffset(request.getEndOffset());
        annotation.setHighlightedText(request.getHighlightedText().trim());
        annotation.setNote(normalizeNote(request.getNote()));
        annotation.setColor(request.getColor());

        BookAnnotation saved = bookAnnotationRepository.save(annotation);
        return ResponseEntity.ok(BookAnnotationDTO.fromEntity(saved));
    }

    @PutMapping("/{bookId}/annotations/{annotationId}")
    public ResponseEntity<?> updateAnnotation(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long annotationId,
            @RequestBody BookAnnotationRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        if (userOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Optional<BookAnnotation> annotationOpt = bookAnnotationRepository
                .findByIdAndUserIdAndBookId(annotationId, userOpt.get().getId(), bookOpt.get().getId());
        if (annotationOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        BookAnnotation annotation = annotationOpt.get();
        if (request.getNote() != null) {
            annotation.setNote(normalizeNote(request.getNote()));
        }
        if (request.getColor() != null) {
            annotation.setColor(request.getColor());
        }

        BookAnnotation saved = bookAnnotationRepository.save(annotation);
        return ResponseEntity.ok(BookAnnotationDTO.fromEntity(saved));
    }

    @DeleteMapping("/{bookId}/annotations/{annotationId}")
    public ResponseEntity<?> deleteAnnotation(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long annotationId) {
        Optional<User> userOpt = getUserFromToken(token);
        if (userOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        Optional<BookAnnotation> annotationOpt = bookAnnotationRepository
                .findByIdAndUserIdAndBookId(annotationId, userOpt.get().getId(), bookOpt.get().getId());
        if (annotationOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        bookAnnotationRepository.delete(annotationOpt.get());
        return ResponseEntity.ok(Map.of("message", "Закладка удалена"));
    }

    private Map<String, Object> progressPayload(UserBook ub, String message) {
        Map<String, Object> result = new HashMap<>();
        result.put("message", message);
        result.put("currentChapter", ub.getCurrentChapter());
        result.put("segmentOrder", ub.getSegmentOrder());
        result.put("segmentProgress", ub.getSegmentProgress());
        result.put("audioPositionMs", ub.getAudioPositionMs());
        result.put("lastMode", ub.getLastMode().name());
        return result;
    }

    private Map<String, Object> ratedBookPayload(UserBook ub, double userAverageRating) {
        Book book = canonicalizationService.canonicalize(ub.getBook());
        Map<String, Object> item = new HashMap<>();
        LocalDateTime ratingDate = ub.getRatedAt() != null ? ub.getRatedAt() : ub.getLastReadAt();
        double centeredSignal = recommendationSignal(ub, userAverageRating);

        item.put("id", book.getId());
        item.put("title", book.getTitle());
        item.put("author", book.getAuthor());
        item.put("coverUrl", book.getCoverUrl());
        item.put("availability", book.getAvailability().name());
        item.put("goodreadsId", book.getGoodreadsId());
        item.put("averageRating", book.getAverageRating());
        item.put("ratingsCount", book.getRatingsCount());
        item.put("reviewCount", book.getReviewCount());
        item.put("language", book.getLanguageCode());
        item.put("rating", ub.getRating());
        item.put("ratedAt", ub.getRatedAt());
        item.put("ratingDate", ratingDate);
        item.put("lastReadAt", ub.getLastReadAt());
        item.put("status", ub.getStatus().name());
        item.put("userAverageRating", userAverageRating);
        item.put("recommendationSignal", centeredSignal);
        item.put("recommendationWeight", centeredSignal);
        return item;
    }

    private double userAverageRating(List<UserBook> ratedBooks) {
        return ratedBooks.stream()
                .map(UserBook::getRating)
                .filter(rating -> rating != null && rating > 0)
                .mapToInt(Integer::intValue)
                .average()
                .orElse(0.0);
    }

    private double recommendationSignal(UserBook ub, double userAverageRating) {
        Integer rating = ub.getRating();
        if (rating == null || rating <= 0 || userAverageRating <= 0) {
            return 0.0;
        }
        return rating - userAverageRating;
    }

    private Integer readInteger(Map<String, Object> request, String key) {
        Object value = request.get(key);
        if (value == null) return null;
        if (value instanceof Number number) return number.intValue();
        try {
            return Integer.parseInt(value.toString());
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private Long readLong(Map<String, Object> request, String key) {
        Object value = request.get(key);
        if (value == null) return null;
        if (value instanceof Number number) return number.longValue();
        try {
            return Long.parseLong(value.toString());
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private Double readDouble(Map<String, Object> request, String key) {
        Object value = request.get(key);
        if (value == null) return null;
        if (value instanceof Number number) return number.doubleValue();
        try {
            return Double.parseDouble(value.toString());
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private ProgressMode readProgressMode(Map<String, Object> request, String key) {
        Object value = request.get(key);
        if (value == null) return null;
        try {
            return ProgressMode.valueOf(value.toString().trim().toUpperCase());
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private String validateAnnotationRequest(Long bookId, BookAnnotationRequest request, boolean requireText) {
        if (request.getChapterOrder() == null || request.getChapterOrder() < 1) {
            return "Неверный номер главы";
        }
        if (request.getStartOffset() == null || request.getEndOffset() == null
                || request.getStartOffset() < 0 || request.getEndOffset() <= request.getStartOffset()) {
            return "Неверный диапазон выделения";
        }
        if (requireText && (request.getHighlightedText() == null || request.getHighlightedText().trim().isEmpty())) {
            return "Текст выделения обязателен";
        }
        return chapterRepository.findByBookIdAndChapterOrder(bookId, request.getChapterOrder())
                .map(chapter -> {
                    String content = chapter.getContent() == null ? "" : chapter.getContent();
                    return request.getEndOffset() > content.length()
                            ? "Диапазон выделения выходит за пределы главы"
                            : "";
                })
                .orElse("Глава не найдена");
    }

    private String normalizeNote(String note) {
        if (note == null || note.trim().isEmpty()) {
            return "";
        }
        return note.trim();
    }
}
