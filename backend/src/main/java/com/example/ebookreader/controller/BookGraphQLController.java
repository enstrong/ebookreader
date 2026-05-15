package com.example.ebookreader.controller;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SchemaMapping;
import org.springframework.stereotype.Controller;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.exception.ResourceNotFoundException;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.repository.ChapterRepository;

@Controller
public class BookGraphQLController {

    private final BookRepository bookRepository;
    private final ChapterRepository chapterRepository;

    @Autowired
    public BookGraphQLController(BookRepository bookRepository, ChapterRepository chapterRepository) {
        this.bookRepository = bookRepository;
        this.chapterRepository = chapterRepository;
    }

    // === QUERIES ===

    @QueryMapping
    public List<Book> allBooks() {
        return bookRepository.findAll();
    }

    @QueryMapping
    public Optional<Book> bookById(@Argument Long id) {
        return bookRepository.findById(id);
    }

    @QueryMapping
    public List<Chapter> chaptersByBookId(@Argument Long bookId) {
        return chapterRepository.findByBookIdOrderByChapterOrderAsc(bookId);
    }

    @QueryMapping
    public Optional<Chapter> chapterByBookIdAndOrder(@Argument Long bookId, @Argument int chapterOrder) {
        return chapterRepository.findByBookIdAndChapterOrder(bookId, chapterOrder);
    }

    // === MUTATIONS ===

    @MutationMapping
    @Transactional
    public Book createBook(@Argument String title, @Argument String author, @Argument String description, @Argument String coverUrl) {
        Book newBook = new Book();
        newBook.setTitle(title);
        newBook.setAuthor(author);
        newBook.setDescription(description != null ? description : "");
        newBook.setCoverUrl(coverUrl);
        return bookRepository.save(newBook);
    }

    @MutationMapping
    @Transactional
    public Book updateBook(@Argument Long id, @Argument String title, @Argument String author, @Argument String description, @Argument String coverUrl) {
        Book existingBook = bookRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена с ID: " + id));

        if (title != null) existingBook.setTitle(title);
        if (author != null) existingBook.setAuthor(author);
        if (description != null) existingBook.setDescription(description);
        if (coverUrl != null) existingBook.setCoverUrl(coverUrl);

        return bookRepository.save(existingBook);
    }

    @MutationMapping
    @Transactional
    public Boolean deleteBook(@Argument Long id) {
        Book book = bookRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена с ID: " + id));

        chapterRepository.deleteAll(chapterRepository.findByBookIdOrderByChapterOrderAsc(id));

        if (book.getCoverUrl() != null && !book.getCoverUrl().isEmpty()) {
            try {
                Path coverPath = Paths.get(book.getCoverUrl());
                Files.deleteIfExists(coverPath);
            } catch (IOException e) {
                System.err.println("Could not delete cover file: " + e.getMessage());
            }
        }

        bookRepository.delete(book);
        return true;
    }

    @MutationMapping
    @Transactional
    public Chapter createChapter(@Argument Long bookId, @Argument int chapterOrder, @Argument String title, @Argument String content) {
        Book book = bookRepository.findById(bookId)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена с ID: " + bookId));

        Chapter chapter = new Chapter();
        chapter.setBook(book);
        chapter.setChapterOrder(chapterOrder);
        chapter.setTitle(title);
        chapter.setContent(content);
        Chapter saved = chapterRepository.save(chapter);
        if (book.getAvailability() == BookAvailability.METADATA_ONLY) {
            book.setAvailability(BookAvailability.TEXT);
            bookRepository.save(book);
        }
        return saved;
    }

    @MutationMapping
    @Transactional
    public Chapter updateChapter(@Argument Long id, @Argument Integer chapterOrder, @Argument String title, @Argument String content) {
        Chapter existingChapter = chapterRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Глава не найдена с ID: " + id));

        if (chapterOrder != null) existingChapter.setChapterOrder(chapterOrder);
        if (title != null) existingChapter.setTitle(title);
        if (content != null) existingChapter.setContent(content);

        return chapterRepository.save(existingChapter);
    }

    @MutationMapping
    @Transactional
    public Boolean deleteChapter(@Argument Long id) {
        Chapter chapter = chapterRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Глава не найдена с ID: " + id));
        chapterRepository.delete(chapter);
        return true;
    }

    // === SCHEMA MAPPINGS (for nested objects) ===

    @SchemaMapping(typeName = "Book", field = "chapters")
    public List<Chapter> getChapters(Book book) {
        return chapterRepository.findByBookIdOrderByChapterOrderAsc(book.getId());
    }
}
