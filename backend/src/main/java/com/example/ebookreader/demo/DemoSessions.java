package com.example.ebookreader.demo;

import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.model.*;
import com.example.ebookreader.repository.*;
import com.example.ebookreader.service.CustomUserDetailsService;
import java.time.*;
import java.util.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

@Service
@EnableScheduling
@ConditionalOnProperty(name = "ebookreader.demo.enabled", havingValue = "true")
public class DemoSessions {
    private final UserRepository users;
    private final BookRepository books;
    private final UserBookRepository library;
    private final BookAnnotationRepository annotations;
    private final ChapterRepository chapters;
    private final JwtUtil jwt;
    private final CustomUserDetailsService details;
    private final JdbcTemplate db;
    public DemoSessions(UserRepository users, BookRepository books, UserBookRepository library,
            BookAnnotationRepository annotations, ChapterRepository chapters, JwtUtil jwt,
            CustomUserDetailsService details, JdbcTemplate db) {
        this.users=users; this.books=books; this.library=library; this.annotations=annotations;
        this.chapters=chapters; this.jwt=jwt; this.details=details; this.db=db;
    }

    @Transactional
    public Map<String,Object> create() {
        // A global ceiling complements per-IP rate limits at the reverse proxy.
        if (db.queryForObject("select count(*) from users where demo_expires_at is not null", Long.class) >= 100) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "The demo is busy. Please try again later.");
        }
        String name = "visitor-" + UUID.randomUUID().toString().substring(0, 12);
        User user = new User(name, name + "@demo.invalid", "!demo-login-disabled", "USER");
        user.setAuthProvider("DEMO");
        user.setDemoExpiresAt(Instant.now().plus(Duration.ofHours(24)));
        users.saveAndFlush(user);
        List<Book> samples = books.findByAvailabilityIn(List.of(BookAvailability.TEXT, BookAvailability.SYNCED))
                .stream().filter(b -> b.getDemoOwnerId() == null)
                .sorted(Comparator.comparingInt((Book b) -> switch(b.getGoodreadsId() == null ? "" : b.getGoodreadsId()) { case "269322" -> 0; case "1885" -> 1; case "13023" -> 2; default -> 3; }))
                .limit(3).toList();
        for (int i=0;i<samples.size();i++) {
            Book book = samples.get(i);
            UserBook entry = add(user, book, i == 0 ? 5 : 4);
            entry.setBookmarked(true);
            entry.setStatus(i == 0 ? ReadingStatus.READING : ReadingStatus.WANT_TO_READ);
            entry.setCurrentChapter(1);
            entry.setSegmentOrder(1);
            entry.setSegmentProgress(i == 0 ? 0.08 : 0.0);
            entry.setLastReadAt(LocalDateTime.now());
            library.save(entry);
        }
        for (String id : List.of("28187", "1885", "5907")) {
            books.findByGoodreadsId(id).ifPresent(book -> add(user, book, 5));
        }
        if (!samples.isEmpty()) {
            Book book = samples.get(0);
            chapters.findByBookIdOrderByChapterOrderAsc(book.getId()).stream().findFirst().ifPresent(chapter -> {
                String content = chapter.getContent();
                if (content != null && !content.isBlank()) {
                    BookAnnotation note = new BookAnnotation();
                    note.setUser(user); note.setBook(book); note.setChapterOrder(chapter.getChapterOrder());
                    note.setStartOffset(0); note.setEndOffset(Math.min(content.length(), 75));
                    note.setHighlightedText(content.substring(0, note.getEndOffset()));
                    note.setNote("A sample note in your private demo. Select text to add your own.");
                    annotations.save(note);
                }
            });
        }
        return payload(user);
    }

    private UserBook add(User user, Book book, int rating) {
        UserBook entry = library.findByUserIdAndBookId(user.getId(),book.getId()).orElseGet(UserBook::new);
        entry.setUser(user); entry.setBook(book); entry.setRating(rating); entry.setRatedAt(LocalDateTime.now());
        entry.setStatus(ReadingStatus.FINISHED);
        return library.save(entry);
    }

    public Map<String,Object> current() { return payload(currentUser()); }
    public User currentUser() {
        if (DemoAccess.userId() == null) throw new ResponseStatusException(HttpStatus.UNAUTHORIZED);
        return users.findById(DemoAccess.userId()).filter(u -> u.getDemoExpiresAt() != null
                && u.getDemoExpiresAt().isAfter(Instant.now()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED));
    }
    private Map<String,Object> payload(User user) {
        return Map.of("token", jwt.generateToken(user.getId(), details.loadUserById(user.getId()), Date.from(user.getDemoExpiresAt())),
                "username", user.getNickname(), "email", user.getEmail(), "role", "USER",
                "authProvider", "DEMO", "expiresAt", user.getDemoExpiresAt().toString());
    }

    @Transactional
    public void end() { deleteVisitor(currentUser().getId()); }

    @Scheduled(fixedDelayString = "${ebookreader.demo.cleanup-ms:900000}", initialDelay = 30000)
    @Transactional
    public void cleanup() {
        List<Long> ids = db.queryForList("select id from users where demo_expires_at < ?", Long.class,
                java.sql.Timestamp.from(Instant.now()));
        ids.forEach(this::deleteVisitor);
    }

    private void deleteVisitor(Long id) {
        // Only demo data; no catalog books or regular accounts can enter this deletion path.
        if (db.queryForObject("select count(*) from users where id=? and demo_expires_at is not null", Long.class, id) == 0) return;
        db.update("update book_review_replies set parent_reply_id=null where user_id=?", id);
        db.update("delete from community_reactions where user_id=?", id);
        db.update("delete from book_review_replies where user_id=?", id);
        db.update("delete from book_annotations where user_id=?", id);
        db.update("delete from user_books where user_id=?", id);
        db.update("delete from chapters where book_id in (select id from books where demo_owner_id=?)", id);
        db.update("delete from demo_uploads where owner_id=?", id);
        db.update("delete from book_genres where book_id in (select id from books where demo_owner_id=?)", id);
        db.update("delete from books where demo_owner_id=?", id);
        db.update("delete from users where id=? and demo_expires_at is not null", id);
    }
}
