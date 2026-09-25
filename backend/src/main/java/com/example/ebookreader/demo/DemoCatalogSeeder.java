package com.example.ebookreader.demo;

import com.example.ebookreader.model.*;
import com.example.ebookreader.repository.*;
import com.example.ebookreader.service.BookCanonicalizationService;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

@Component
@Order(-100)
@ConditionalOnProperty(name="ebookreader.demo.enabled",havingValue="true")
public class DemoCatalogSeeder implements CommandLineRunner {
    private final String path;
    private final JdbcTemplate db;
    private final ObjectMapper mapper;
    private final BookRepository books;
    private final ChapterRepository chapters;
    private final BookCanonicalizationService canonical;
    public DemoCatalogSeeder(@Value("${ebookreader.demo.catalog-path:}") String path, JdbcTemplate db,
            ObjectMapper mapper, BookRepository books, ChapterRepository chapters, BookCanonicalizationService canonical) {
        this.path=path; this.db=db; this.mapper=mapper; this.books=books; this.chapters=chapters; this.canonical=canonical;
    }
    @Override @Transactional
    public void run(String... args) throws Exception {
        if (path.isBlank()) return; // Unit/integration tests provide a small catalog fixture.
        var catalog=mapper.readTree(Path.of(path).toFile());
        if (db.queryForObject("select count(*) from books where goodreads_id is not null",Long.class) < catalog.size()) {
        Map<String,Long> genreIds=new HashMap<>();
        db.query("select id,name from genres", rs -> { genreIds.put(rs.getString("name"),rs.getLong("id")); });
        for(var row:catalog) {
            String id=row.path("goodreadsId").asText();
            db.update("insert into books (goodreads_id,title,author,description,cover_url,external_url,average_rating,ratings_count,page_count,language,availability) values (?,?,?,?,?,?,?,?,?,?, 'METADATA_ONLY') on conflict (goodreads_id) do nothing",
                id,row.path("title").asText(),row.path("author").asText(),row.path("description").asText(),row.path("coverUrl").asText(),
                row.path("externalUrl").asText(),row.path("averageRating").asDouble(),row.path("ratingsCount").asInt(),row.path("pageCount").asInt(),row.path("language").asText());
            Long bookId=db.queryForObject("select id from books where goodreads_id=?",Long.class,id);
            for(var genre:row.path("genres")) {
                String name=genre.asText().trim(); if(name.isEmpty()) continue;
                // Genre names in the model metadata are semicolon-separated, stable labels.
                Long genreId=genreIds.get(name);
                if(genreId==null) {
                    db.update("insert into genres (name) values (?)",name);
                    genreId=db.queryForObject("select id from genres where name=?",Long.class,name);
                    genreIds.put(name,genreId);
                }
                if(db.queryForObject("select count(*) from book_genres where book_id=? and genre_id=?",Long.class,bookId,genreId)==0)
                    db.update("insert into book_genres (book_id,genre_id) values (?,?)",bookId,genreId);
            }
        }
        }
        seedText("1885","Pride and Prejudice","Jane Austen","pride-and-prejudice.txt");
        seedText("13023","Alice's Adventures in Wonderland","Lewis Carroll","alice.txt");
        canonical.reload();
    }
    private void seedText(String id,String title,String author,String resource) throws Exception {
        Book book=books.findByGoodreadsId(id).orElseGet(Book::new);
        book.setGoodreadsId(id); book.setTitle(title); book.setAuthor(author); book.setLanguageCode("eng");
        book.setAvailability(BookAvailability.TEXT);
        book.setDescription("Complete public-domain text from Project Gutenberg. Read, highlight, translate, and save your progress.");
        books.saveAndFlush(book);
        if(chapters.countByBookId(book.getId())>0) return;
        String text=new ClassPathResource("demo/books/"+resource).getContentAsString(StandardCharsets.UTF_8);
        // Paragraph-aligned parts keep browser pagination responsive, without dropping the source text or license.
        String[] paragraphs=text.replace("\r\n","\n").split("\n\n");
        StringBuilder part=new StringBuilder(); int order=1;
        for(String paragraph:paragraphs) {
            part.append(paragraph).append("\n\n");
            if(part.length()>=16000) { saveChapter(book,order++,part.toString()); part.setLength(0); }
        }
        if(!part.isEmpty()) saveChapter(book,order,part.toString());
    }
    private void saveChapter(Book book,int order,String text) {
        Chapter chapter=new Chapter(); chapter.setBook(book); chapter.setChapterOrder(order);
        chapter.setTitle("Part "+order); chapter.setContent(text); chapter.setSourceType("PROJECT_GUTENBERG");
        chapters.save(chapter);
    }
}
