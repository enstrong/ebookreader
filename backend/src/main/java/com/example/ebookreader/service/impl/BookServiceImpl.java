package com.example.ebookreader.service.impl;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.dto.AudioTrackDTO;
import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.model.AudioTrack;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.repository.AudioTrackRepository;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.repository.ChapterRepository;
import com.example.ebookreader.service.BookService;

@Service
public class BookServiceImpl implements BookService {

    private final BookRepository bookRepository;
    private final ChapterRepository chapterRepository;
    private final AudioTrackRepository audioTrackRepository;

    @Autowired
    public BookServiceImpl(BookRepository bookRepository, ChapterRepository chapterRepository, AudioTrackRepository audioTrackRepository) {
        this.bookRepository = bookRepository;
        this.chapterRepository = chapterRepository;
        this.audioTrackRepository = audioTrackRepository;
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> getAllBooks() {
        return bookRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> getLibraryBooks() {
        return bookRepository.findByAvailabilityIn(
                List.of(BookAvailability.TEXT, BookAvailability.AUDIO, BookAvailability.SYNCED));
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> searchBooks(String query) {
        if (query == null || query.trim().isEmpty()) {
            return bookRepository.findAll();
        }
        return bookRepository.findAll().stream()
                .filter(book -> 
                    safeLower(book.getTitle()).contains(query.toLowerCase()) ||
                    safeLower(book.getAuthor()).contains(query.toLowerCase()))
                .collect(Collectors.toList());
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<Book> getBookById(Long id) {
        return bookRepository.findById(id);
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
}
