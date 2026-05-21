package com.example.ebookreader.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.UserBook;
import com.example.ebookreader.model.ReadingStatus;

@Repository
public interface UserBookRepository extends JpaRepository<UserBook, Long> {
    Optional<UserBook> findByUserIdAndBookId(Long userId, Long bookId);
    List<UserBook> findByUserIdAndBookmarkedTrue(Long userId);
    List<UserBook> findByUserIdAndStatusOrderByLastReadAtDesc(Long userId, ReadingStatus status);
    @Query("select ub from UserBook ub where ub.user.id = :userId and ub.rating is not null order by coalesce(ub.ratedAt, ub.lastReadAt) desc")
    List<UserBook> findRatedByUserIdOrderByRatingDateDesc(@Param("userId") Long userId);
    @Query("select ub from UserBook ub join fetch ub.book where ub.user.id = :userId")
    List<UserBook> findByUserIdWithBook(@Param("userId") Long userId);
    List<UserBook> findByUserId(Long userId);
    
    @Modifying
    @Transactional
    void deleteByBookId(Long bookId);
}
