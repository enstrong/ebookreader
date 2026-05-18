package com.example.ebookreader.service;

import java.util.List;
import java.util.Optional;

import com.example.ebookreader.dto.BookPageResponse;
import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.dto.AudioTrackDTO;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.Book;

public interface BookService {
    List<Book> getAllBooks();
    BookPageResponse getBooksPage(int page, int size, String query, List<String> languages, List<String> genres, Double minRating, List<String> contentFeatures, BookAvailability availability, String sort);
    List<Book> getLibraryBooks();
    List<Book> searchBooks(String query);
    Optional<Book> getBookById(Long id);
    List<ChapterDTO> getBookChapters(Long bookId);
    Optional<ChapterDTO> getChapter(Long bookId, int chapterOrder);
    List<AudioTrackDTO> getAudioTracks(Long bookId);
}
