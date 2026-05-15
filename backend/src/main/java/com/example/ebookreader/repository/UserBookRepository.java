package com.example.ebookreader.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.UserBook;

@Repository
public interface UserBookRepository extends JpaRepository<UserBook, Long> {
    Optional<UserBook> findByUserIdAndBookId(Long userId, Long bookId);
    List<UserBook> findByUserIdAndBookmarkedTrue(Long userId);
    List<UserBook> findByUserId(Long userId);
    
    @Modifying
    @Transactional
    void deleteByBookId(Long bookId);
}
