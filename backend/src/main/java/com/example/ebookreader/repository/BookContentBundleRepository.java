package com.example.ebookreader.repository;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.BookContentBundle;

@Repository
public interface BookContentBundleRepository extends JpaRepository<BookContentBundle, Long> {
    List<BookContentBundle> findByBookIdOrderByCreatedAtDesc(Long bookId);

    @Modifying
    @Transactional
    void deleteByBookId(Long bookId);
}
