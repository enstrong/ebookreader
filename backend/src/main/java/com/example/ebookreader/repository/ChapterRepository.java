package com.example.ebookreader.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.example.ebookreader.model.Chapter;

@Repository
public interface ChapterRepository extends JpaRepository<Chapter, Long> {
    List<Chapter> findByBookIdOrderByChapterOrderAsc(Long bookId);
    Optional<Chapter> findByBookIdAndChapterOrder(Long bookId, int chapterOrder);
    long countByBookId(Long bookId);
}
