package com.example.ebookreader.demo;

import com.example.ebookreader.model.*;
import com.example.ebookreader.repository.*;
import jakarta.persistence.EntityManager;
import java.util.Map;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.*;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/demo")
@ConditionalOnProperty(name = "ebookreader.demo.enabled", havingValue = "true")
public class DemoController {
    private final DemoSessions sessions;
    private final BookRepository books;
    private final ChapterRepository chapters;
    private final UserBookRepository library;
    private final EntityManager entityManager;
    private final JdbcTemplate db;
    public DemoController(DemoSessions sessions, BookRepository books, ChapterRepository chapters,
            UserBookRepository library, EntityManager entityManager, JdbcTemplate db) {
        this.sessions=sessions; this.books=books; this.chapters=chapters; this.library=library;
        this.entityManager=entityManager; this.db=db;
    }
    @PostMapping("/session") public Map<String,Object> create() { return sessions.create(); }
    @GetMapping("/session") public Map<String,Object> current() { return sessions.current(); }
    @DeleteMapping("/session") public ResponseEntity<Void> end() { sessions.end(); return ResponseEntity.noContent().build(); }
    @GetMapping("/health") public Map<String,Object> health() {
        db.queryForObject("select 1", Integer.class);
        return Map.of("status","ready","database",true);
    }
    @PostMapping(value="/uploads", consumes=MediaType.MULTIPART_FORM_DATA_VALUE)
    @Transactional
    public Map<String,Object> upload(@RequestParam("file") MultipartFile file) throws Exception {
        User user=sessions.currentUser();
        // Serialize uploads for this visitor so concurrent requests cannot bypass the quota.
        entityManager.lock(entityManager.find(User.class,user.getId()), jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
        if (file.isEmpty() || file.getSize()>10*1024*1024) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Choose a book under 10 MB");
        if (db.queryForObject("select count(*) from demo_uploads where owner_id=?", Long.class,user.getId())>=10)
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Maximum 10 uploads per demo");
        long stored=db.queryForObject("select coalesce(sum(octet_length(content)),0) from demo_uploads where owner_id=?",Long.class,user.getId());
        if(stored+file.getSize()>20*1024*1024) throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,"Maximum 20 MB per demo");
        String filename=file.getOriginalFilename()==null ? "book.txt" : file.getOriginalFilename().replace('\\','/');
        filename=filename.substring(filename.lastIndexOf('/')+1);
        if(filename.length()>180) throw new ResponseStatusException(HttpStatus.BAD_REQUEST,"Filename too long");
        byte[] bytes=file.getBytes();
        DemoBookParser.Parsed parsed;
        try { parsed=DemoBookParser.parse(filename,bytes); }
        catch(Exception e) { return Map.of("error","This book could not be read. Choose an unencrypted EPUB, FB2 or UTF-8 TXT under 10 MB (8 MB expanded)."); }
        Book book=new Book(); book.setTitle(shorten(parsed.title(),1000)); book.setAuthor(shorten(parsed.author(),1000));
        book.setDescription("Your private demo upload. Automatically deleted with your temporary account.");
        book.setAvailability(BookAvailability.TEXT); book.setDemoOwnerId(user.getId());
        book.setLanguageCode("en"); books.saveAndFlush(book);
        int order=1;
        for(var part:parsed.chapters()) {
            Chapter chapter=new Chapter(); chapter.setBook(book); chapter.setChapterOrder(order++);
            chapter.setTitle(shorten(part.title(),250)); chapter.setContent(part.text()); chapter.setSourceType("DEMO_UPLOAD");
            chapters.save(chapter);
        }
        DemoUpload original=new DemoUpload(); original.setOwnerId(user.getId()); original.setBookId(book.getId());
        original.setFilename(filename); original.setContent(bytes); entityManager.persist(original);
        UserBook entry=new UserBook(); entry.setUser(user); entry.setBook(book); entry.setBookmarked(true);
        entry.setStatus(ReadingStatus.WANT_TO_READ); library.save(entry);
        return Map.of("id",book.getId(),"title",book.getTitle(),"chapters",parsed.chapters().size());
    }
    private static String shorten(String text,int size) { return text.substring(0,Math.min(text.length(),size)); }
}
