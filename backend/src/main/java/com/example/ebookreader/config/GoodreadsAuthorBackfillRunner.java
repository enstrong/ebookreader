package com.example.ebookreader.config;

import java.util.ArrayList;
import java.util.List;

import org.springframework.boot.CommandLineRunner;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.Book;
import com.example.ebookreader.repository.BookRepository;
import com.example.ebookreader.service.BookCanonicalizationService;
import com.example.ebookreader.service.GoodreadsAuthorNameService;

@Component
@Order(0)
public class GoodreadsAuthorBackfillRunner implements CommandLineRunner {

    private final BookRepository bookRepository;
    private final GoodreadsAuthorNameService authorNameService;
    private final BookCanonicalizationService canonicalizationService;

    public GoodreadsAuthorBackfillRunner(
            BookRepository bookRepository,
            GoodreadsAuthorNameService authorNameService,
            BookCanonicalizationService canonicalizationService) {
        this.bookRepository = bookRepository;
        this.authorNameService = authorNameService;
        this.canonicalizationService = canonicalizationService;
    }

    @Override
    @Transactional
    public void run(String... args) {
        List<Book> changed = new ArrayList<>();
        for (Book book : bookRepository.findAll()) {
            String author = book.getAuthor();
            if (author == null || author.isBlank()) {
                authorNameService.resolveAuthorNamesForBook(book.getGoodreadsId())
                        .ifPresent(resolved -> {
                            book.setAuthor(resolved);
                            changed.add(book);
                        });
                continue;
            }
            if (!authorNameService.isNumericAuthorList(author)) {
                continue;
            }

            authorNameService.resolveAuthorNames(author)
                    .filter(resolved -> !resolved.equals(author))
                    .ifPresent(resolved -> {
                        book.setAuthor(resolved);
                        changed.add(book);
                    });
        }

        if (!changed.isEmpty()) {
            bookRepository.saveAll(changed);
            canonicalizationService.reload();
            System.out.printf("Resolved Goodreads author names for %d books.%n", changed.size());
        }
    }
}
