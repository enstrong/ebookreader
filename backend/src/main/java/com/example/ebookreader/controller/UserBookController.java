package com.example.ebookreader.controller;

import java.time.LocalDateTime;
import java.util.ArrayList;
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
import com.example.ebookreader.dto.BookReviewDTO;
import com.example.ebookreader.dto.BookReviewRequest;
import com.example.ebookreader.dto.FavoriteQuoteDTO;
import com.example.ebookreader.dto.LookupRequest;
import com.example.ebookreader.dto.ReviewReplyDTO;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAnnotation;
import com.example.ebookreader.model.BookReviewReply;
import com.example.ebookreader.model.CommunityReaction;
import com.example.ebookreader.model.ProgressMode;
import com.example.ebookreader.model.ReadingStatus;
import com.example.ebookreader.model.User;
import com.example.ebookreader.model.UserBook;
import com.example.ebookreader.repository.BookAnnotationRepository;
import com.example.ebookreader.repository.BookReviewReplyRepository;
import com.example.ebookreader.repository.ChapterRepository;
import com.example.ebookreader.repository.CommunityReactionRepository;
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
    private BookReviewReplyRepository bookReviewReplyRepository;

    @Autowired
    private CommunityReactionRepository communityReactionRepository;

    @Autowired
    private JwtUtil jwtUtil;

    @Autowired
    private LookupService lookupService;

    @Autowired
    private BookCanonicalizationService canonicalizationService;

    private static final int MAX_REVIEW_CHARS = 6000;
    private static final int MAX_QUOTE_WORDS = 120;
    private static final String TARGET_REVIEW = "BOOK_REVIEW";
    private static final String TARGET_REPLY = "REVIEW_REPLY";
    private static final String TARGET_QUOTE = "QUOTE";

    private Optional<User> getUserFromToken(String token) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        return userRepository.findByNickname(username);
    }

    private UserBook getOrCreateUserBook(User user, Book book) {
        List<UserBook> existing = userBookRepository.findAllByUserIdAndBookIdOrderByIdAsc(user.getId(), book.getId());
        if (existing.isEmpty()) {
            UserBook ub = new UserBook();
            ub.setUser(user);
            ub.setBook(book);
            ub.setCurrentChapter(1);
            return ub;
        }
        UserBook primary = existing.get(0);
        if (existing.size() > 1) {
            for (int index = 1; index < existing.size(); index++) {
                mergeUserBook(primary, existing.get(index));
            }
            userBookRepository.deleteAll(existing.subList(1, existing.size()));
            userBookRepository.save(primary);
        }
        return primary;
    }

    private Optional<UserBook> findUserBook(User user, Book book) {
        List<UserBook> existing = userBookRepository.findAllByUserIdAndBookIdOrderByIdAsc(user.getId(), book.getId());
        if (existing.isEmpty()) {
            return Optional.empty();
        }
        UserBook primary = existing.get(0);
        if (existing.size() > 1) {
            for (int index = 1; index < existing.size(); index++) {
                mergeUserBook(primary, existing.get(index));
            }
            userBookRepository.deleteAll(existing.subList(1, existing.size()));
            userBookRepository.save(primary);
        }
        return Optional.of(primary);
    }

    private void mergeUserBook(UserBook primary, UserBook duplicate) {
        if (duplicate.isBookmarked()) {
            primary.setBookmarked(true);
        }
        if (duplicate.getRating() != null) {
            primary.setRating(duplicate.getRating());
            primary.setRatedAt(latest(primary.getRatedAt(), duplicate.getRatedAt()));
        }
        if (duplicate.getReviewText() != null && !duplicate.getReviewText().isBlank()
                && (primary.getReviewText() == null || primary.getReviewText().isBlank()
                || latest(primary.getReviewUpdatedAt(), duplicate.getReviewUpdatedAt()) == duplicate.getReviewUpdatedAt())) {
            primary.setReviewText(duplicate.getReviewText());
            primary.setReviewCreatedAt(latest(primary.getReviewCreatedAt(), duplicate.getReviewCreatedAt()));
            primary.setReviewUpdatedAt(latest(primary.getReviewUpdatedAt(), duplicate.getReviewUpdatedAt()));
        }
        primary.setStartedAt(earliestNonNull(primary.getStartedAt(), duplicate.getStartedAt()));
        primary.setFinishedAt(latest(primary.getFinishedAt(), duplicate.getFinishedAt()));
        primary.setLastReadAt(latest(primary.getLastReadAt(), duplicate.getLastReadAt()));

        if (readingStatusRank(duplicate.getStatus()) > readingStatusRank(primary.getStatus())) {
            primary.setStatus(duplicate.getStatus());
        }
        if (isProgressNewer(duplicate, primary)) {
            primary.setCurrentChapter(duplicate.getCurrentChapter());
            primary.setSegmentOrder(duplicate.getSegmentOrder());
            primary.setSegmentProgress(duplicate.getSegmentProgress());
            primary.setAudioPositionMs(duplicate.getAudioPositionMs());
            primary.setLastMode(duplicate.getLastMode());
        }
    }

    private boolean isProgressNewer(UserBook candidate, UserBook current) {
        LocalDateTime candidateReadAt = candidate.getLastReadAt();
        LocalDateTime currentReadAt = current.getLastReadAt();
        if (candidateReadAt == null) {
            return false;
        }
        return currentReadAt == null || candidateReadAt.isAfter(currentReadAt);
    }

    private int readingStatusRank(ReadingStatus status) {
        if (status == ReadingStatus.READING) {
            return 2;
        }
        if (status == ReadingStatus.FINISHED) {
            return 3;
        }
        return 1;
    }

    private LocalDateTime latest(LocalDateTime first, LocalDateTime second) {
        if (first == null) {
            return second;
        }
        if (second == null) {
            return first;
        }
        return first.isAfter(second) ? first : second;
    }

    private LocalDateTime earliestNonNull(LocalDateTime first, LocalDateTime second) {
        if (first == null) {
            return second;
        }
        if (second == null) {
            return first;
        }
        return first.isBefore(second) ? first : second;
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

    private void clearPhantomReadingStatus(UserBook ub) {
        if (ub.getStatus() == ReadingStatus.READING
                && ub.getStartedAt() == null
                && ub.getFinishedAt() == null) {
            ub.setStatus(ReadingStatus.WANT_TO_READ);
            ub.setLastReadAt(null);
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
        ub.setHiddenFromLibrary(false);
        if (ub.getStatus() == ReadingStatus.WANT_TO_READ) {
            ub.setLastReadAt(LocalDateTime.now());
        }
        if (ub.getStartedAt() == null && ub.getFinishedAt() == null) {
            ub.setStatus(ReadingStatus.WANT_TO_READ);
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
                        .flatMap(book -> findUserBook(user, book)))
                .map(ub -> {
                    ub.setBookmarked(false);
                    userBookRepository.save(ub);
                    return ResponseEntity.ok(Map.of("message", "Удалено из закладок"));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{bookId}/library")
    public ResponseEntity<?> removeFromLibrary(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        return findUserBook(userOpt.get(), bookOpt.get())
                .map(ub -> {
                    ub.setBookmarked(false);
                    ub.setHiddenFromLibrary(true);
                    ub.setStatus(ReadingStatus.WANT_TO_READ);
                    ub.setStartedAt(null);
                    ub.setFinishedAt(null);
                    ub.setLastReadAt(null);
                    userBookRepository.save(ub);
                    return ResponseEntity.ok(Map.of("message", "Удалено из библиотеки"));
                })
                .orElse(ResponseEntity.notFound().build());
    }

    // Получить все закладки пользователя
    @GetMapping("/bookmarks")
    public ResponseEntity<?> getBookmarks(@RequestHeader("Authorization") String token) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        return userRepository.findByNickname(username)
                .map(user -> {
                    List<UserBook> bookmarks = userBookRepository.findLibraryByUserId(user.getId());
                    Set<Long> seenBookIds = new HashSet<>();
                    List<Map<String, Object>> result = new ArrayList<>();
                    for (UserBook ub : bookmarks) {
                        if (ub.getBook() == null || !seenBookIds.add(ub.getBook().getId())) {
                            continue;
                        }
                        if (canonicalizationService.findCanonicalById(ub.getBook().getId())
                                .map(book -> !book.getId().equals(ub.getBook().getId()))
                                .orElse(false)) {
                            continue;
                        }
                        result.add(libraryBookPayload(ub));
                    }

                    for (BookAnnotation annotation : bookAnnotationRepository.findByUserIdOrderByUpdatedAtDesc(user.getId())) {
                        Book book = annotation.getBook();
                        if (book == null || !seenBookIds.add(book.getId())) {
                            continue;
                        }
                        Optional<UserBook> existingUserBook = userBookRepository.findByUserIdAndBookId(user.getId(), book.getId());
                        if (existingUserBook.map(UserBook::isHiddenFromLibrary).orElse(false)) {
                            continue;
                        }
                        if (canonicalizationService.findCanonicalById(book.getId())
                                .map(canonical -> !canonical.getId().equals(book.getId()))
                                .orElse(false)) {
                            continue;
                        }
                        Map<String, Object> item = new HashMap<>();
                        item.put("id", book.getId());
                        item.put("title", book.getTitle());
                        item.put("author", book.getAuthor());
                        item.put("coverUrl", book.getCoverUrl());
                        item.put("genres", book.getGenres().stream()
                                .map(genre -> genre.getName())
                                .collect(Collectors.toList()));
                        item.put("averageRating", book.getAverageRating());
                        item.put("ratingsCount", book.getRatingsCount());
                        item.put("language", book.getLanguageCode());
                        item.put("currentChapter", annotation.getChapterOrder());
                        item.put("segmentOrder", annotation.getChapterOrder());
                        item.put("segmentProgress", 0.0);
                        item.put("audioPositionMs", 0);
                        item.put("lastMode", ProgressMode.TEXT.name());
                        item.put("availability", book.getAvailability().name());
                        item.put("isBookmarked", false);
                        item.put("status", ReadingStatus.READING.name());
                        item.put("lastReadAt", annotation.getUpdatedAt());
                        result.add(item);
                    }
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
        ub.setHiddenFromLibrary(false);
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
        ub.setHiddenFromLibrary(false);
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
        ub.setHiddenFromLibrary(false);
        applyStatus(ub, ReadingStatus.FINISHED);
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of(
                "message", "Книга отмечена как прочитанная",
                "status", ub.getStatus().name(),
                "rating", ub.getRating() == null ? 0 : ub.getRating()
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
        clearPhantomReadingStatus(ub);
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
        clearPhantomReadingStatus(ub);
        userBookRepository.save(ub);

        return ResponseEntity.ok(Map.of(
                "message", "Оценка удалена",
                "rating", 0
        ));
    }

    @GetMapping("/{bookId}/reviews")
    public ResponseEntity<?> getBookReviews(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        List<UserBook> reviews = userBookRepository.findReviewsByBookId(bookOpt.get().getId());
        List<Long> reviewIds = reviews.stream().map(UserBook::getId).collect(Collectors.toList());
        List<BookReviewReply> replies = reviewIds.isEmpty()
                ? List.of()
                : bookReviewReplyRepository.findByReviewIdInOrderByCreatedAtAsc(reviewIds);

        Map<Long, List<BookReviewReply>> repliesByReview = replies.stream()
                .collect(Collectors.groupingBy(reply -> reply.getReview().getId()));
        Map<Long, List<BookReviewReply>> repliesByParent = replies.stream()
                .filter(reply -> reply.getParentReply() != null)
                .collect(Collectors.groupingBy(reply -> reply.getParentReply().getId()));

        List<BookReviewDTO> result = reviews.stream()
                .map(review -> reviewPayload(review, repliesByReview.getOrDefault(review.getId(), List.of()),
                        repliesByParent, userOpt.get()))
                .collect(Collectors.toList());
        return ResponseEntity.ok(result);
    }

    @PutMapping("/{bookId}/reviews")
    public ResponseEntity<?> saveBookReview(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @RequestBody BookReviewRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        String text = normalizeReviewText(request.getText());
        if (text.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Текст отзыва обязателен"));
        }
        if (text.length() > MAX_REVIEW_CHARS) {
            return ResponseEntity.badRequest().body(Map.of("message", "Отзыв слишком длинный"));
        }
        Integer rating = request.getRating();
        if (rating == null || rating < 1 || rating > 5) {
            return ResponseEntity.badRequest().body(Map.of("message", "Оценка должна быть от 1 до 5"));
        }

        UserBook ub = getOrCreateUserBook(userOpt.get(), bookOpt.get());
        LocalDateTime now = LocalDateTime.now();
        if (ub.getReviewCreatedAt() == null) {
            ub.setReviewCreatedAt(now);
        }
        ub.setReviewUpdatedAt(now);
        ub.setReviewText(text);
        ub.setRating(rating);
        ub.setRatedAt(now);
        ub.setLastReadAt(now);
        clearPhantomReadingStatus(ub);
        UserBook saved = userBookRepository.save(ub);
        return ResponseEntity.ok(reviewPayload(saved, List.of(), Map.of(), userOpt.get()));
    }

    @PutMapping("/{bookId}/reviews/{reviewId}/vote")
    public ResponseEntity<?> voteReview(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long reviewId,
            @RequestBody BookReviewRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        Optional<UserBook> reviewOpt = userBookRepository.findById(reviewId);
        if (userOpt.isEmpty() || bookOpt.isEmpty() || reviewOpt.isEmpty()
                || !bookOpt.get().getId().equals(reviewOpt.get().getBook().getId())) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(votePayload(applyVote(userOpt.get(), TARGET_REVIEW, reviewId, request.getVote()),
                TARGET_REVIEW, reviewId));
    }

    @PostMapping("/{bookId}/reviews/{reviewId}/replies")
    public ResponseEntity<?> createReviewReply(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long reviewId,
            @RequestBody BookReviewRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        Optional<UserBook> reviewOpt = userBookRepository.findById(reviewId);
        if (userOpt.isEmpty() || bookOpt.isEmpty() || reviewOpt.isEmpty()
                || !bookOpt.get().getId().equals(reviewOpt.get().getBook().getId())) {
            return ResponseEntity.notFound().build();
        }
        String text = normalizeReviewText(request.getText());
        if (text.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Текст ответа обязателен"));
        }
        if (text.length() > MAX_REVIEW_CHARS) {
            return ResponseEntity.badRequest().body(Map.of("message", "Ответ слишком длинный"));
        }

        BookReviewReply reply = new BookReviewReply();
        reply.setReview(reviewOpt.get());
        reply.setUser(userOpt.get());
        reply.setText(text);
        if (request.getParentReplyId() != null) {
            Optional<BookReviewReply> parent = bookReviewReplyRepository
                    .findByIdAndReviewId(request.getParentReplyId(), reviewId);
            if (parent.isEmpty()) {
                return ResponseEntity.badRequest().body(Map.of("message", "Родительский ответ не найден"));
            }
            reply.setParentReply(parent.get());
        }
        BookReviewReply saved = bookReviewReplyRepository.save(reply);
        return ResponseEntity.ok(replyPayload(saved, Map.of(), userOpt.get()));
    }

    @PutMapping("/{bookId}/reviews/replies/{replyId}/vote")
    public ResponseEntity<?> voteReply(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long replyId,
            @RequestBody BookReviewRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<BookReviewReply> replyOpt = bookReviewReplyRepository.findById(replyId);
        if (userOpt.isEmpty() || replyOpt.isEmpty()
                || !replyOpt.get().getReview().getBook().getId().equals(findCanonicalBook(bookId).map(Book::getId).orElse(null))) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(votePayload(applyVote(userOpt.get(), TARGET_REPLY, replyId, request.getVote()),
                TARGET_REPLY, replyId));
    }

    @GetMapping("/{bookId}/quotes")
    public ResponseEntity<?> getBookQuotes(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        List<FavoriteQuoteDTO> quotes = bookAnnotationRepository
                .findByBookIdAndPublishedQuoteTrueOrderByPublishedQuoteAtDescCreatedAtDesc(bookOpt.get().getId())
                .stream()
                .map(annotation -> quotePayload(annotation, userOpt.get()))
                .collect(Collectors.toList());
        return ResponseEntity.ok(quotes);
    }

    @GetMapping("/quotes/favorites")
    public ResponseEntity<?> getMyFavoriteQuotes(@RequestHeader("Authorization") String token) {
        Optional<User> userOpt = getUserFromToken(token);
        if (userOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        List<FavoriteQuoteDTO> quotes = bookAnnotationRepository
                .findByUserIdAndPublishedQuoteTrueOrderByPublishedQuoteAtDescCreatedAtDesc(userOpt.get().getId())
                .stream()
                .map(annotation -> quotePayload(annotation, userOpt.get()))
                .collect(Collectors.toList());
        return ResponseEntity.ok(quotes);
    }

    @PostMapping("/{bookId}/annotations/{annotationId}/quote")
    public ResponseEntity<?> publishQuote(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long annotationId) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        if (userOpt.isEmpty() || bookOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        Optional<BookAnnotation> annotationOpt = bookAnnotationRepository
                .findByIdAndUserIdAndBookId(annotationId, userOpt.get().getId(), bookOpt.get().getId());
        if (annotationOpt.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        BookAnnotation annotation = annotationOpt.get();
        if (wordCount(annotation.getHighlightedText()) > MAX_QUOTE_WORDS) {
            return ResponseEntity.badRequest().body(Map.of("message", "Цитата не может быть длиннее 120 слов"));
        }
        annotation.setPublishedQuote(true);
        if (annotation.getPublishedQuoteAt() == null) {
            annotation.setPublishedQuoteAt(LocalDateTime.now());
        }
        BookAnnotation saved = bookAnnotationRepository.save(annotation);
        return ResponseEntity.ok(quotePayload(saved, userOpt.get()));
    }

    @PutMapping("/{bookId}/quotes/{quoteId}/vote")
    public ResponseEntity<?> voteQuote(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId,
            @PathVariable Long quoteId,
            @RequestBody BookReviewRequest request) {
        Optional<User> userOpt = getUserFromToken(token);
        Optional<Book> bookOpt = findCanonicalBook(bookId);
        Optional<BookAnnotation> quoteOpt = bookAnnotationRepository.findById(quoteId);
        if (userOpt.isEmpty() || bookOpt.isEmpty() || quoteOpt.isEmpty()
                || !quoteOpt.get().isPublishedQuote()
                || !bookOpt.get().getId().equals(quoteOpt.get().getBook().getId())) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(votePayload(applyVote(userOpt.get(), TARGET_QUOTE, quoteId, request.getVote()),
                TARGET_QUOTE, quoteId));
    }

    // Получить прогресс чтения книги
    @GetMapping("/{bookId}/progress")
    public ResponseEntity<?> getProgress(
            @RequestHeader("Authorization") String token,
            @PathVariable Long bookId) {
        String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        return userRepository.findByNickname(username)
                .flatMap(user -> findCanonicalBook(bookId)
                        .flatMap(book -> findUserBook(user, book)))
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

        UserBook ub = getOrCreateUserBook(userOpt.get(), bookOpt.get());
        ub.setSegmentOrder(request.getChapterOrder());
        ub.setHiddenFromLibrary(false);
        ub.setLastReadAt(LocalDateTime.now());
        if (ub.getStatus() == ReadingStatus.WANT_TO_READ) {
            applyStatus(ub, ReadingStatus.READING);
        }
        userBookRepository.save(ub);

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

    private Map<String, Object> libraryBookPayload(UserBook ub) {
        Map<String, Object> item = new HashMap<>();
        item.put("id", ub.getBook().getId());
        item.put("title", ub.getBook().getTitle());
        item.put("author", ub.getBook().getAuthor());
        item.put("coverUrl", ub.getBook().getCoverUrl());
        item.put("genres", ub.getBook().getGenres().stream()
                .map(genre -> genre.getName())
                .collect(Collectors.toList()));
        item.put("averageRating", ub.getBook().getAverageRating());
        item.put("ratingsCount", ub.getBook().getRatingsCount());
        item.put("language", ub.getBook().getLanguageCode());
        item.put("currentChapter", ub.getCurrentChapter());
        item.put("segmentOrder", ub.getSegmentOrder());
        item.put("segmentProgress", ub.getSegmentProgress());
        item.put("audioPositionMs", ub.getAudioPositionMs());
        item.put("lastMode", ub.getLastMode().name());
        item.put("availability", ub.getBook().getAvailability().name());
        item.put("isBookmarked", ub.isBookmarked());
        item.put("status", ub.getStatus().name());
        item.put("lastReadAt", ub.getLastReadAt());
        return item;
    }

    private BookReviewDTO reviewPayload(
            UserBook review,
            List<BookReviewReply> flatReplies,
            Map<Long, List<BookReviewReply>> repliesByParent,
            User currentUser) {
        BookReviewDTO dto = new BookReviewDTO();
        dto.setId(review.getId());
        dto.setBookId(review.getBook().getId());
        dto.setRating(review.getRating());
        dto.setText(review.getReviewText());
        dto.setNickname(displayName(review.getUser()));
        dto.setAvatarInitial(avatarInitial(review.getUser()));
        dto.setLikes((int) communityReactionRepository.countByTargetTypeAndTargetIdAndValue(TARGET_REVIEW, review.getId(), 1));
        dto.setDislikes((int) communityReactionRepository.countByTargetTypeAndTargetIdAndValue(TARGET_REVIEW, review.getId(), -1));
        dto.setCurrentUserVote(currentUserVote(currentUser, TARGET_REVIEW, review.getId()));
        dto.setCurrentUserReview(review.getUser().getId().equals(currentUser.getId()));
        dto.setCreatedAt(review.getReviewCreatedAt());
        dto.setUpdatedAt(review.getReviewUpdatedAt());
        dto.setReplies(flatReplies.stream()
                .filter(reply -> reply.getParentReply() == null)
                .map(reply -> replyPayload(reply, repliesByParent, currentUser))
                .collect(Collectors.toList()));
        return dto;
    }

    private ReviewReplyDTO replyPayload(
            BookReviewReply reply,
            Map<Long, List<BookReviewReply>> repliesByParent,
            User currentUser) {
        ReviewReplyDTO dto = new ReviewReplyDTO();
        dto.setId(reply.getId());
        dto.setText(reply.getText());
        dto.setNickname(displayName(reply.getUser()));
        dto.setAvatarInitial(avatarInitial(reply.getUser()));
        dto.setLikes((int) communityReactionRepository.countByTargetTypeAndTargetIdAndValue(TARGET_REPLY, reply.getId(), 1));
        dto.setDislikes((int) communityReactionRepository.countByTargetTypeAndTargetIdAndValue(TARGET_REPLY, reply.getId(), -1));
        dto.setCurrentUserVote(currentUserVote(currentUser, TARGET_REPLY, reply.getId()));
        dto.setCreatedAt(reply.getCreatedAt());
        dto.setReplies(repliesByParent.getOrDefault(reply.getId(), List.of()).stream()
                .map(child -> replyPayload(child, repliesByParent, currentUser))
                .collect(Collectors.toList()));
        return dto;
    }

    private FavoriteQuoteDTO quotePayload(BookAnnotation annotation, User currentUser) {
        FavoriteQuoteDTO dto = new FavoriteQuoteDTO();
        dto.setId(annotation.getId());
        dto.setBookId(annotation.getBook().getId());
        dto.setBookTitle(annotation.getBook().getTitle());
        dto.setBookAuthor(annotation.getBook().getAuthor());
        dto.setText(annotation.getHighlightedText());
        dto.setChapterOrder(annotation.getChapterOrder());
        dto.setNickname(displayName(annotation.getUser()));
        dto.setAvatarInitial(avatarInitial(annotation.getUser()));
        dto.setLikes((int) communityReactionRepository.countByTargetTypeAndTargetIdAndValue(TARGET_QUOTE, annotation.getId(), 1));
        dto.setDislikes((int) communityReactionRepository.countByTargetTypeAndTargetIdAndValue(TARGET_QUOTE, annotation.getId(), -1));
        dto.setCurrentUserVote(currentUserVote(currentUser, TARGET_QUOTE, annotation.getId()));
        dto.setCurrentUserQuote(annotation.getUser().getId().equals(currentUser.getId()));
        dto.setPublishedAt(annotation.getPublishedQuoteAt());
        return dto;
    }

    private int applyVote(User user, String targetType, Long targetId, Integer requestedVote) {
        int vote = requestedVote == null ? 0 : Math.max(-1, Math.min(1, requestedVote));
        Optional<CommunityReaction> existing = communityReactionRepository
                .findByUserIdAndTargetTypeAndTargetId(user.getId(), targetType, targetId);
        if (vote == 0) {
            existing.ifPresent(communityReactionRepository::delete);
            return 0;
        }
        CommunityReaction reaction = existing.orElseGet(CommunityReaction::new);
        reaction.setUser(user);
        reaction.setTargetType(targetType);
        reaction.setTargetId(targetId);
        reaction.setValue(vote);
        communityReactionRepository.save(reaction);
        return vote;
    }

    private Map<String, Object> votePayload(int currentUserVote, String targetType, Long targetId) {
        return Map.of(
                "currentUserVote", currentUserVote,
                "likes", communityReactionRepository.countByTargetTypeAndTargetIdAndValue(targetType, targetId, 1),
                "dislikes", communityReactionRepository.countByTargetTypeAndTargetIdAndValue(targetType, targetId, -1)
        );
    }

    private int currentUserVote(User user, String targetType, Long targetId) {
        return communityReactionRepository
                .findByUserIdAndTargetTypeAndTargetId(user.getId(), targetType, targetId)
                .map(CommunityReaction::getValue)
                .orElse(0);
    }

    private String normalizeReviewText(String text) {
        return text == null ? "" : text.trim();
    }

    private int wordCount(String text) {
        if (text == null || text.trim().isEmpty()) {
            return 0;
        }
        return text.trim().split("\\s+").length;
    }

    private String displayName(User user) {
        if (user.getNickname() != null && !user.getNickname().isBlank()) {
            return user.getNickname();
        }
        return "User";
    }

    private String avatarInitial(User user) {
        String name = displayName(user);
        return name.isEmpty() ? "U" : name.substring(0, 1).toUpperCase();
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
        item.put("reviewText", ub.getReviewText());
        item.put("reviewCreatedAt", ub.getReviewCreatedAt());
        item.put("reviewUpdatedAt", ub.getReviewUpdatedAt());
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
