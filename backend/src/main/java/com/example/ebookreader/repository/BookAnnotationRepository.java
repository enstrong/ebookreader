package com.example.ebookreader.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.BookAnnotation;

@Repository
public interface BookAnnotationRepository extends JpaRepository<BookAnnotation, Long> {
    List<BookAnnotation> findByUserIdAndBookIdOrderByChapterOrderAscStartOffsetAsc(Long userId, Long bookId);
    List<BookAnnotation> findByUserIdAndBookIdAndChapterOrderOrderByStartOffsetAsc(Long userId, Long bookId, Integer chapterOrder);
    Optional<BookAnnotation> findByIdAndUserIdAndBookId(Long id, Long userId, Long bookId);

    @Modifying
    @Transactional
    void deleteByBookId(Long bookId);
}
