package com.example.ebookreader.service.impl;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.exception.ResourceNotFoundException;
import com.example.ebookreader.model.AudioTrack;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.BookContentBundle;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.model.Genre;
import com.example.ebookreader.model.User;
import com.example.ebookreader.repository.AudioTrackRepository;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.repository.BookContentBundleRepository;
import com.example.ebookreader.repository.ChapterRepository;
import com.example.ebookreader.repository.GenreRepository;
import com.example.ebookreader.repository.UserBookRepository;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.service.AdminService;

@Service
public class AdminServiceImpl implements AdminService {

    private final BookRepository bookRepository;
    private final ChapterRepository chapterRepository;
    private final GenreRepository genreRepository;
    private final UserRepository userRepository;
    private final UserBookRepository userBookRepository;
    private final AudioTrackRepository audioTrackRepository;
    private final BookContentBundleRepository bookContentBundleRepository;

    @Autowired
    public AdminServiceImpl(BookRepository bookRepository, ChapterRepository chapterRepository, GenreRepository genreRepository, UserRepository userRepository, UserBookRepository userBookRepository, AudioTrackRepository audioTrackRepository, BookContentBundleRepository bookContentBundleRepository) {
        this.bookRepository = bookRepository;
        this.chapterRepository = chapterRepository;
        this.genreRepository = genreRepository;
        this.userRepository = userRepository;
        this.userBookRepository = userBookRepository;
        this.audioTrackRepository = audioTrackRepository;
        this.bookContentBundleRepository = bookContentBundleRepository;
    }

    @Override
    @Transactional(readOnly = true)
    public List<Book> getAllBooks() {
        return bookRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<Book> getBookById(Long id) {
        return bookRepository.findById(id);
    }

    @Override
    @Transactional
    public Book createBook(String title, String author, String description, List<String> genres, String language, MultipartFile cover) throws IOException {
        if (title == null || title.trim().isEmpty()) {
            throw new IllegalArgumentException("Название книги обязательно");
        }
        if (author == null || author.trim().isEmpty()) {
            throw new IllegalArgumentException("Автор книги обязателен");
        }

        Book newBook = new Book();
        newBook.setTitle(title);
        newBook.setAuthor(author);
        newBook.setDescription(description != null ? description : "");
        newBook.setLanguageCode(language != null ? language.trim() : null);
        newBook.setAvailability(BookAvailability.METADATA_ONLY);

        if (genres != null && !genres.isEmpty()) {
            newBook.setGenres(resolveGenres(genres));
        }

        if (cover != null && !cover.isEmpty()) {
            Path uploadPath = Paths.get("assets/covers");
            if (!Files.exists(uploadPath)) {
                Files.createDirectories(uploadPath);
            }
            String fileName = System.currentTimeMillis() + "_" + cover.getOriginalFilename();
            Path filePath = uploadPath.resolve(fileName);
            Files.copy(cover.getInputStream(), filePath, StandardCopyOption.REPLACE_EXISTING);
            newBook.setCoverUrl(fileName);
        }

        return bookRepository.save(newBook);
    }

    @Override
    @Transactional
    public Book updateBook(Long id, Book bookDetails) {
        Book existingBook = bookRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена"));

        if (bookDetails.getTitle() != null) {
            existingBook.setTitle(bookDetails.getTitle());
        }
        if (bookDetails.getAuthor() != null) {
            existingBook.setAuthor(bookDetails.getAuthor());
        }
        if (bookDetails.getDescription() != null) {
            existingBook.setDescription(bookDetails.getDescription());
        }
        if (bookDetails.getCoverUrl() != null) {
            existingBook.setCoverUrl(bookDetails.getCoverUrl());
        }
        if (bookDetails.getGenres() != null) {
            existingBook.setGenres(resolveGenres(bookDetails.getGenres().stream().map(Genre::getName).toList()));
        }
        if (bookDetails.getLanguageCode() != null) {
            existingBook.setLanguageCode(bookDetails.getLanguageCode());
        }
        return bookRepository.save(existingBook);
    }

    @Override
    @Transactional
    public Book updateBookAvailability(Long id, BookAvailability availability) {
        Book existingBook = bookRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена"));
        existingBook.setAvailability(availability);
        return bookRepository.save(existingBook);
    }

    /**
     * Удаляет книгу, все её главы и связи с пользователями.
     * Перед удалением книги необходимо очистить таблицу user_books, чтобы избежать ошибок внешнего ключа.
     */
    @Override
    @Transactional
    public void deleteBook(Long id) {
        Book book = bookRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена"));

        // Удаляем связи пользователей с книгой
        userBookRepository.deleteByBookId(id);

        // Удаляем главы книги
        chapterRepository.deleteAll(chapterRepository.findByBookIdOrderByChapterOrderAsc(id));
        audioTrackRepository.deleteByBookId(id);
        bookContentBundleRepository.deleteByBookId(id);

        if (book.getCoverUrl() != null && !book.getCoverUrl().isEmpty()) {
            try {
                // Если в БД хранится только имя файла, добавляем путь к папке
                String coverUrl = book.getCoverUrl();
                Path coverPath;
                if (coverUrl.contains("/")) {
                    coverPath = Paths.get(coverUrl);
                } else {
                    coverPath = Paths.get("assets/covers").resolve(coverUrl);
                }
                Files.deleteIfExists(coverPath);
            } catch (IOException e) {
                System.err.println("Could not delete cover file: " + e.getMessage());
            }
        }
        bookRepository.delete(book);
    }

    @Override
    public Resource getCover(String filename) throws IOException {
        Path filePath = Paths.get("assets/covers").resolve(filename);
        Resource resource = new UrlResource(filePath.toUri());

        if (resource.exists() && resource.isReadable()) {
            return resource;
        } else {
            throw new ResourceNotFoundException("Обложка не найдена: " + filename);
        }
    }

    @Override
    @Transactional(readOnly = true)
    public List<Chapter> getChapters(Long bookId) {
        return chapterRepository.findByBookIdOrderByChapterOrderAsc(bookId);
    }

    private Set<Genre> resolveGenres(List<String> genreNames) {
        Set<Genre> genreSet = new HashSet<>();
        for (String rawName : genreNames) {
            if (rawName == null || rawName.trim().isEmpty()) {
                continue;
            }
            String normalized = rawName.trim();
            Genre genre = genreRepository.findByName(normalized)
                    .orElseGet(() -> new Genre(normalized));
            genreSet.add(genre);
        }
        return genreSet;
    }

    @Override
    @Transactional
    public Chapter createChapter(Long bookId, ChapterDTO dto) {
        Book book = bookRepository.findById(bookId)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена"));

        Chapter chapter = new Chapter();
        chapter.setBook(book);
        chapter.setChapterOrder(dto.getChapterOrder());
        chapter.setTitle(dto.getTitle());
        chapter.setContent(dto.getContent());
        chapter.setContentBundle(getOrCreateManualBundle(book));
        chapter.setSourceType("ADMIN");
        Chapter saved = chapterRepository.save(chapter);
        updateAvailabilityFromAssets(book);
        return saved;
    }

    @Override
    @Transactional
    public Chapter updateChapter(Long bookId, Long chapterId, ChapterDTO dto) {
        Chapter existingChapter = chapterRepository.findById(chapterId)
                .orElseThrow(() -> new ResourceNotFoundException("Глава не найдена"));

        if (!existingChapter.getBook().getId().equals(bookId)) {
            throw new IllegalArgumentException("Глава не принадлежит указанной книге");
        }

        if (dto.getChapterOrder() != null) existingChapter.setChapterOrder(dto.getChapterOrder());
        if (dto.getTitle() != null) existingChapter.setTitle(dto.getTitle());
        if (dto.getContent() != null) existingChapter.setContent(dto.getContent());

        Chapter saved = chapterRepository.save(existingChapter);
        updateAvailabilityFromAssets(existingChapter.getBook());
        return saved;
    }

    @Override
    @Transactional
    public void deleteChapter(Long bookId, Long chapterId) {
        Chapter chapter = chapterRepository.findById(chapterId)
                .orElseThrow(() -> new ResourceNotFoundException("Глава не найдена"));

        if (!chapter.getBook().getId().equals(bookId)) {
            throw new IllegalArgumentException("Глава не принадлежит указанной книге");
        }
        Book book = chapter.getBook();
        chapterRepository.delete(chapter);
        updateAvailabilityFromAssets(book);
    }

    @Override
    @Transactional
    public AudioTrack createAudioTrack(Long bookId, Integer segmentOrder, String title, Long durationMs, MultipartFile audio) throws IOException {
        if (segmentOrder == null || segmentOrder < 1) {
            throw new IllegalArgumentException("Неверный номер сегмента");
        }
        if (audio == null || audio.isEmpty()) {
            throw new IllegalArgumentException("Аудиофайл обязателен");
        }

        Book book = bookRepository.findById(bookId)
                .orElseThrow(() -> new ResourceNotFoundException("Книга не найдена"));

        Path uploadPath = Paths.get("assets/audio").resolve(bookId.toString());
        if (!Files.exists(uploadPath)) {
            Files.createDirectories(uploadPath);
        }

        String originalName = audio.getOriginalFilename() == null ? "audio" : audio.getOriginalFilename();
        String cleanName = originalName.replaceAll("[^a-zA-Z0-9._-]", "_");
        String fileName = System.currentTimeMillis() + "_" + cleanName;
        Path filePath = uploadPath.resolve(fileName);
        Files.copy(audio.getInputStream(), filePath, StandardCopyOption.REPLACE_EXISTING);

        AudioTrack track = new AudioTrack();
        track.setBook(book);
        track.setSegmentOrder(segmentOrder);
        track.setTitle(title != null && !title.isBlank() ? title.trim() : "Сегмент " + segmentOrder);
        track.setDurationMs(durationMs);
        track.setAudioPath(filePath.toString());
        track.setOriginalFileName(originalName);
        track.setContentType(audio.getContentType() != null ? audio.getContentType() : "audio/mpeg");

        AudioTrack saved = audioTrackRepository.save(track);
        updateAvailabilityFromAssets(book);
        return saved;
    }

    @Override
    @Transactional(readOnly = true)
    public Resource getAudioTrackResource(Long bookId, Long trackId) throws IOException {
        AudioTrack track = audioTrackRepository.findByIdAndBookId(trackId, bookId)
                .orElseThrow(() -> new ResourceNotFoundException("Аудиотрек не найден"));
        Resource resource = new UrlResource(Paths.get(track.getAudioPath()).toUri());
        if (resource.exists() && resource.isReadable()) {
            return resource;
        }
        throw new ResourceNotFoundException("Аудиофайл не найден: " + track.getAudioPath());
    }

    private void updateAvailabilityFromAssets(Book book) {
        long textCount = chapterRepository.countByBookId(book.getId());
        long audioCount = audioTrackRepository.countByBookId(book.getId());

        if (textCount > 0 && audioCount > 0) {
            book.setAvailability(BookAvailability.SYNCED);
        } else if (textCount > 0) {
            book.setAvailability(BookAvailability.TEXT);
        } else if (audioCount > 0) {
            book.setAvailability(BookAvailability.AUDIO);
        } else if (book.getAvailability() != BookAvailability.PDF_ONLY) {
            book.setAvailability(BookAvailability.METADATA_ONLY);
        }
        bookRepository.save(book);
    }

    private BookContentBundle getOrCreateManualBundle(Book book) {
        return bookContentBundleRepository.findByBookIdOrderByCreatedAtDesc(book.getId()).stream()
                .filter(bundle -> "ADMIN_IMPORT".equals(bundle.getSourceType()))
                .findFirst()
                .orElseGet(() -> {
                    BookContentBundle bundle = new BookContentBundle();
                    bundle.setBook(book);
                    bundle.setSourceType("ADMIN_IMPORT");
                    bundle.setSourceName("Admin curated import");
                    bundle.setLanguageCode(book.getLanguageCode());
                    return bookContentBundleRepository.save(bundle);
                });
    }

    @Override
    @Transactional(readOnly = true)
    public List<User> getAllUsers() {
        return userRepository.findAll();
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<User> getUserById(Long id) {
        return userRepository.findById(id);
    }

    @Override
    @Transactional
    public User updateUserRole(Long id, String newRole) {
        User user = userRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Пользователь не найден"));
        user.setRole(newRole);
        return userRepository.save(user);
    }

    @Override
    @Transactional
    public void deleteUser(Long id) {
        userRepository.deleteById(id);
    }
}
