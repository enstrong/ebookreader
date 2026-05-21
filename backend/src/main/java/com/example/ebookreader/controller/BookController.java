package com.example.ebookreader.controller;

import java.io.IOException;
import java.io.InputStream;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpRange;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.util.MultiValueMap;

import com.example.ebookreader.dto.AudioTrackDTO;
import com.example.ebookreader.dto.BookPageResponse;
import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.ReadingStatus;
import com.example.ebookreader.repository.UserBookRepository;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.config.DemoAudiobookSeeder;
import com.example.ebookreader.service.AdminService;
import com.example.ebookreader.service.BookService; // Импортируем сервис

@RestController
@RequestMapping("/api/books" )
@CrossOrigin(origins = "*")
public class BookController {

    private final BookService bookService; // Используем сервис
    private final AdminService adminService;
    private final UserBookRepository userBookRepository;
    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;
    private final DemoAudiobookSeeder demoAudiobookSeeder;

    @Autowired
    public BookController(BookService bookService, AdminService adminService, UserBookRepository userBookRepository, UserRepository userRepository, JwtUtil jwtUtil, DemoAudiobookSeeder demoAudiobookSeeder) {
        this.bookService = bookService;
        this.adminService = adminService;
        this.userBookRepository = userBookRepository;
        this.userRepository = userRepository;
        this.jwtUtil = jwtUtil;
        this.demoAudiobookSeeder = demoAudiobookSeeder;
    }

    @GetMapping
    public ResponseEntity<BookPageResponse> getAllBooks(
            @RequestParam(required = false, defaultValue = "0") int page,
            @RequestParam(required = false, defaultValue = "50") int size,
            @RequestParam MultiValueMap<String, String> params) {
        ensureDemoAudiobookSeeded();
        return ResponseEntity.ok(bookService.getBooksPage(
                page,
                size,
                first(params, "query", ""),
                splitCommaValues(params.get("languages")),
                rawValues(params.get("genres")),
                parseDouble(first(params, "minRating", null)),
                splitCommaValues(params.get("features")),
                parseAvailability(first(params, "availability", null)),
                first(params, "sort", "popular")
        ));
    }

    @GetMapping("/library")
    public ResponseEntity<List<Book>> getLibraryBooks(
            @RequestHeader(value = "Authorization", required = false) String token) {
        if (token == null || !token.startsWith("Bearer ")) {
            return ResponseEntity.ok(List.of());
        }

        try {
            String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
            return userRepository.findByNickname(username)
                    .map(user -> userBookRepository
                            .findByUserIdAndStatusOrderByLastReadAtDesc(user.getId(), ReadingStatus.READING)
                            .stream()
                            .map(userBook -> userBook.getBook())
                            .toList())
                    .map(ResponseEntity::ok)
                    .orElseGet(() -> ResponseEntity.ok(List.of()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
    }

    @GetMapping("/demo-audiobook")
    public ResponseEntity<Book> getDemoAudiobook(
            @RequestHeader(value = "Authorization", required = false) String token) {
        assertAuthenticated(token);
        return demoAudiobookSeeder.getDemoBook()
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/search")
    public ResponseEntity<List<Book>> searchBooks(
            @RequestParam(required = false, defaultValue = "") String query) {
        ensureDemoAudiobookSeeded();
        return ResponseEntity.ok(bookService.searchBooks(query));
    }

    private BookAvailability parseAvailability(String rawAvailability) {
        if (rawAvailability == null || rawAvailability.isBlank()) {
            return null;
        }
        try {
            return BookAvailability.valueOf(rawAvailability.trim().toUpperCase());
        } catch (IllegalArgumentException ex) {
            return null;
        }
    }

    private String first(MultiValueMap<String, String> params, String key, String fallback) {
        String value = params.getFirst(key);
        return value == null ? fallback : value;
    }

    private Double parseDouble(String rawValue) {
        if (rawValue == null || rawValue.isBlank()) {
            return null;
        }
        try {
            return Double.parseDouble(rawValue);
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private List<String> splitCommaValues(List<String> values) {
        if (values == null) {
            return List.of();
        }
        return values.stream()
                .flatMap(value -> java.util.Arrays.stream(value.split(",")))
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .toList();
    }

    private List<String> rawValues(List<String> values) {
        if (values == null) {
            return List.of();
        }
        return values.stream()
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .toList();
    }

    @GetMapping("/{id}")
    public ResponseEntity<Book> getBookById(@PathVariable Long id) {
        ensureDemoAudiobookSeeded();
        return bookService.getBookById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/{bookId}/chapters")
    public ResponseEntity<List<ChapterDTO>> getBookChapters(@PathVariable Long bookId) {
        ensureDemoAudiobookSeeded();
        return ResponseEntity.ok(bookService.getBookChapters(bookId));
    }

    @GetMapping("/{bookId}/chapters/{chapterOrder}")
    public ResponseEntity<ChapterDTO> getChapter(
            @PathVariable Long bookId,
            @PathVariable int chapterOrder) {
        return bookService.getChapter(bookId, chapterOrder)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/{bookId}/audio-tracks")
    public ResponseEntity<List<AudioTrackDTO>> getAudioTracks(
            @PathVariable Long bookId,
            @RequestHeader(value = "Authorization", required = false) String token) {
        ensureDemoAudiobookSeeded();
        assertAudioAccess(token, bookId);
        return ResponseEntity.ok(bookService.getAudioTracks(bookId));
    }

    @GetMapping("/{bookId}/audio-tracks/{trackId}/stream")
    public ResponseEntity<?> streamAudioTrack(
            @PathVariable Long bookId,
            @PathVariable Long trackId,
            @RequestHeader HttpHeaders headers) throws IOException {
        ensureDemoAudiobookSeeded();
        assertAudioAccess(headers.getFirst(HttpHeaders.AUTHORIZATION), bookId);
        Resource resource = adminService.getAudioTrackResource(bookId, trackId);
        MediaType contentType = MediaType.APPLICATION_OCTET_STREAM;
        if (resource.getFilename() != null) {
            String filename = resource.getFilename().toLowerCase();
            if (filename.endsWith(".mp3")) {
                contentType = MediaType.parseMediaType("audio/mpeg");
            } else if (filename.endsWith(".m4a")) {
                contentType = MediaType.parseMediaType("audio/mp4");
            } else if (filename.endsWith(".ogg")) {
                contentType = MediaType.parseMediaType("audio/ogg");
            } else if (filename.endsWith(".wav")) {
                contentType = MediaType.parseMediaType("audio/wav");
            }
        }

        List<HttpRange> ranges = headers.getRange();
        if (!ranges.isEmpty()) {
            long contentLength = resource.contentLength();
            long start = ranges.get(0).getRangeStart(contentLength);
            long end = ranges.get(0).getRangeEnd(contentLength);
            long rangeLength = end - start + 1;
            byte[] region = readResourceRange(resource, start, rangeLength);
            return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT)
                    .contentType(contentType)
                    .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                    .header(HttpHeaders.CONTENT_RANGE, "bytes " + start + "-" + end + "/" + contentLength)
                    .contentLength(rangeLength)
                    .body(region);
        }

        return ResponseEntity.ok()
                .contentType(contentType)
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .body(resource);
    }

    private byte[] readResourceRange(Resource resource, long start, long rangeLength) throws IOException {
        try (InputStream inputStream = resource.getInputStream()) {
            inputStream.skipNBytes(start);
            return inputStream.readNBytes(Math.toIntExact(rangeLength));
        }
    }

    private void ensureDemoAudiobookSeeded() {
        demoAudiobookSeeder.seed();
    }

    private void assertAudioAccess(String token, Long bookId) {
        if (demoAudiobookSeeder.isDemoBook(bookId)) {
            assertAuthenticated(token);
            return;
        }

        var user = authenticatedUser(token);
        boolean hasAccess = "ADMIN".equalsIgnoreCase(user.getRole()) || user.isAudioSubscriptionActive();
        if (!hasAccess) {
            throw new ResponseStatusException(HttpStatus.PAYMENT_REQUIRED, "Для прослушивания нужна аудиоподписка");
        }
    }

    private void assertAuthenticated(String token) {
        authenticatedUser(token);
    }

    private com.example.ebookreader.model.User authenticatedUser(String token) {
        if (token == null || !token.startsWith("Bearer ")) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Нужна авторизация");
        }

        try {
            String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
            return userRepository.findByNickname(username)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Неверный токен"));
        } catch (ResponseStatusException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Неверный токен");
        }
    }
}
