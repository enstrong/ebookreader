package com.example.ebookreader.config;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StreamUtils;

import com.example.ebookreader.model.AudioTrack;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;
import com.example.ebookreader.model.BookContentBundle;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.repository.AudioTrackRepository;
import com.example.ebookreader.repository.BookContentBundleRepository;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.repository.ChapterRepository;

@Component
public class DemoAudiobookSeeder implements CommandLineRunner {
    private static final String GOODREADS_ID = "269322";
    private static final String AUDIO_PATH = "assets/audio/demo/the_raven_librivox.mp3";
    private static final String SOURCE_HREF = "https://www.gutenberg.org/ebooks/1065";

    private final BookRepository bookRepository;
    private final ChapterRepository chapterRepository;
    private final AudioTrackRepository audioTrackRepository;
    private final BookContentBundleRepository bundleRepository;
    private final boolean enabled;

    public DemoAudiobookSeeder(
            BookRepository bookRepository,
            ChapterRepository chapterRepository,
            AudioTrackRepository audioTrackRepository,
            BookContentBundleRepository bundleRepository,
            @Value("${ebookreader.demo.seed-audiobook:true}") boolean enabled) {
        this.bookRepository = bookRepository;
        this.chapterRepository = chapterRepository;
        this.audioTrackRepository = audioTrackRepository;
        this.bundleRepository = bundleRepository;
        this.enabled = enabled;
    }

    @Override
    public void run(String... args) throws Exception {
        seed();
    }

    @Transactional
    public void seed() {
        if (!enabled) {
            return;
        }

        Book book = findRavenBook()
                .orElseGet(this::createRavenBook);
        if (book.getAuthor() == null || book.getAuthor().isBlank()) {
            book.setAuthor("Edgar Allan Poe");
        }
        if (book.getGoodreadsId() == null || book.getGoodreadsId().isBlank()) {
            book.setGoodreadsId(GOODREADS_ID);
        }

        List<Chapter> chapters = chapterRepository.findByBookIdOrderByChapterOrderAsc(book.getId());
        Chapter ravenSegment = chapters.stream()
                .filter(chapter -> SOURCE_HREF.equals(chapter.getSourceHref()))
                .findFirst()
                .orElseGet(() -> createRavenSegment(book, chapters));

        boolean hasDemoAudio = audioTrackRepository.findByBookIdOrderBySegmentOrderAsc(book.getId()).stream()
                .anyMatch(track -> "the_raven_librivox.mp3".equals(track.getOriginalFileName()));
        String audioPath = resolvedAudioPath();
        if (!hasDemoAudio && audioPath != null) {
            AudioTrack track = new AudioTrack();
            track.setBook(book);
            track.setSegmentOrder(ravenSegment.getChapterOrder());
            track.setTitle("The Raven");
            track.setAudioPath(audioPath);
            track.setOriginalFileName("the_raven_librivox.mp3");
            track.setContentType("audio/mpeg");
            track.setDurationMs(570974L);
            audioTrackRepository.save(track);
        }

        if (chapterRepository.countByBookId(book.getId()) > 0
                && audioTrackRepository.countByBookId(book.getId()) > 0) {
            book.setAvailability(BookAvailability.SYNCED);
        } else if (chapterRepository.countByBookId(book.getId()) > 0) {
            book.setAvailability(BookAvailability.TEXT);
        } else if (audioTrackRepository.countByBookId(book.getId()) > 0) {
            book.setAvailability(BookAvailability.AUDIO);
        }
        bookRepository.save(book);
    }

    private Optional<Book> findRavenBook() {
        Optional<Book> byGoodreadsId = bookRepository.findByGoodreadsId(GOODREADS_ID);
        if (byGoodreadsId.isPresent()) {
            return byGoodreadsId;
        }

        return bookRepository.findAll().stream()
                .filter(book -> book.getTitle() != null)
                .filter(book -> book.getTitle().trim().equalsIgnoreCase("The Raven and Other Poems"))
                .findFirst();
    }

    private String resolvedAudioPath() {
        if (Files.exists(Path.of(AUDIO_PATH))) {
            return AUDIO_PATH;
        }

        String repoRootPath = "backend/" + AUDIO_PATH;
        if (Files.exists(Path.of(repoRootPath))) {
            return repoRootPath;
        }

        return null;
    }

    private Book createRavenBook() {
        Book book = new Book();
        book.setTitle("The Raven and Other Poems");
        book.setAuthor("Edgar Allan Poe");
        book.setDescription("A curated demo edition containing a synchronized public-domain text and LibriVox recording of \"The Raven\".");
        book.setCoverUrl("https://images.gr-assets.com/books/1297913274m/269322.jpg");
        book.setGoodreadsId(GOODREADS_ID);
        book.setAverageRating(4.30);
        book.setRatingsCount(34934);
        book.setReviewCount(297);
        book.setExternalUrl("https://www.goodreads.com/book/show/269322.The_Raven_and_Other_Poems");
        book.setLanguageCode("eng");
        book.setPageCount(73);
        book.setAvailability(BookAvailability.METADATA_ONLY);
        return bookRepository.save(book);
    }

    private Chapter createRavenSegment(Book book, List<Chapter> existingChapters) {
        BookContentBundle bundle = new BookContentBundle();
        bundle.setBook(book);
        bundle.setSourceType("PROJECT_GUTENBERG");
        bundle.setSourceName("Project Gutenberg #1065");
        bundle.setOriginalFileName("1065.txt.utf-8");
        bundle.setLanguageCode("eng");
        BookContentBundle savedBundle = bundleRepository.save(bundle);

        int segmentOrder = nextSegmentOrder(existingChapters);
        Chapter chapter = new Chapter();
        chapter.setBook(book);
        chapter.setChapterOrder(segmentOrder);
        chapter.setTitle("The Raven");
        chapter.setContent(readRavenText());
        chapter.setContentBundle(savedBundle);
        chapter.setSourceType("PROJECT_GUTENBERG");
        chapter.setSourceHref(SOURCE_HREF);
        return chapterRepository.save(chapter);
    }

    private int nextSegmentOrder(List<Chapter> existingChapters) {
        boolean hasFirstSegment = existingChapters.stream()
                .anyMatch(chapter -> Integer.valueOf(1).equals(chapter.getChapterOrder()));
        if (!hasFirstSegment) {
            return 1;
        }
        return existingChapters.stream()
                .map(Chapter::getChapterOrder)
                .filter(order -> order != null)
                .max(Comparator.naturalOrder())
                .orElse(0) + 1;
    }

    private String readRavenText() {
        try {
            ClassPathResource resource = new ClassPathResource("demo/the_raven.txt");
            return StreamUtils.copyToString(resource.getInputStream(), StandardCharsets.UTF_8);
        } catch (IOException ex) {
            throw new IllegalStateException("Could not read demo text for The Raven", ex);
        }
    }
}
