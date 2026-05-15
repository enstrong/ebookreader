package com.example.ebookreader.controller;

import java.io.IOException;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.ResourceRegion;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpRange;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.example.ebookreader.dto.AudioTrackDTO;
import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.service.AdminService;
import com.example.ebookreader.service.BookService; // Импортируем сервис

@RestController
@RequestMapping("/api/books" )
@CrossOrigin(origins = "*")
public class BookController {

    private final BookService bookService; // Используем сервис
    private final AdminService adminService;

    @Autowired
    public BookController(BookService bookService, AdminService adminService) {
        this.bookService = bookService;
        this.adminService = adminService;
    }

    @GetMapping
    public ResponseEntity<List<Book>> getAllBooks() {
        return ResponseEntity.ok(bookService.getAllBooks());
    }

    @GetMapping("/library")
    public ResponseEntity<List<Book>> getLibraryBooks() {
        return ResponseEntity.ok(bookService.getLibraryBooks());
    }

    @GetMapping("/search")
    public ResponseEntity<List<Book>> searchBooks(
            @RequestParam(required = false, defaultValue = "") String query) {
        return ResponseEntity.ok(bookService.searchBooks(query));
    }

    @GetMapping("/{id}")
    public ResponseEntity<Book> getBookById(@PathVariable Long id) {
        return bookService.getBookById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/{bookId}/chapters")
    public ResponseEntity<List<ChapterDTO>> getBookChapters(@PathVariable Long bookId) {
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
    public ResponseEntity<List<AudioTrackDTO>> getAudioTracks(@PathVariable Long bookId) {
        return ResponseEntity.ok(bookService.getAudioTracks(bookId));
    }

    @GetMapping("/{bookId}/audio-tracks/{trackId}/stream")
    public ResponseEntity<?> streamAudioTrack(
            @PathVariable Long bookId,
            @PathVariable Long trackId,
            @RequestHeader HttpHeaders headers) throws IOException {
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
            ResourceRegion region = resourceRegion(resource, ranges.get(0));
            return ResponseEntity.status(HttpStatus.PARTIAL_CONTENT)
                    .contentType(contentType)
                    .body(region);
        }

        return ResponseEntity.ok()
                .contentType(contentType)
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .body(resource);
    }

    private ResourceRegion resourceRegion(Resource resource, HttpRange range) throws IOException {
        long contentLength = resource.contentLength();
        long start = range.getRangeStart(contentLength);
        long end = range.getRangeEnd(contentLength);
        long rangeLength = Math.min(1024 * 1024, end - start + 1);
        return new ResourceRegion(resource, start, rangeLength);
    }
}
