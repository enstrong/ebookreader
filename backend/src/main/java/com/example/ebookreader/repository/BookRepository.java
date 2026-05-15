package com.example.ebookreader.repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.BookAvailability;

@Repository
public interface BookRepository extends JpaRepository<Book, Long> {
    Optional<Book> findByGoodreadsId(String goodreadsId);
    List<Book> findByGoodreadsIdIn(Collection<String> goodreadsIds);
    List<Book> findByAvailabilityIn(Collection<BookAvailability> availability);
}
