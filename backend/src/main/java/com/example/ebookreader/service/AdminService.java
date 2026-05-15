package com.example.ebookreader.service;

import java.io.IOException;
import java.util.List;
import java.util.Optional;

import org.springframework.core.io.Resource;
import org.springframework.web.multipart.MultipartFile;

import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.model.AudioTrack;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.model.User;

public interface AdminService {
    List<Book> getAllBooks();
    Optional<Book> getBookById(Long id);
    Book createBook(String title, String author, String description, List<String> genres, String language, MultipartFile cover) throws IOException;
    Book updateBook(Long id, Book bookDetails);
    Book updateBookAvailability(Long id, BookAvailability availability);
    void deleteBook(Long id);
    Resource getCover(String filename) throws IOException;

    List<Chapter> getChapters(Long bookId);
    Chapter createChapter(Long bookId, ChapterDTO dto);
    Chapter updateChapter(Long bookId, Long chapterId, ChapterDTO dto);
    void deleteChapter(Long bookId, Long chapterId);
    AudioTrack createAudioTrack(Long bookId, Integer segmentOrder, String title, Long durationMs, MultipartFile audio) throws IOException;
    Resource getAudioTrackResource(Long bookId, Long trackId) throws IOException;

    List<User> getAllUsers();
    Optional<User> getUserById(Long id);
    User updateUserRole(Long id, String newRole);
    void deleteUser(Long id);
}
