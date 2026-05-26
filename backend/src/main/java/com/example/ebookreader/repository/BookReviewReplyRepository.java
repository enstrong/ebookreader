package com.example.ebookreader.repository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.example.ebookreader.model.BookReviewReply;

@Repository
public interface BookReviewReplyRepository extends JpaRepository<BookReviewReply, Long> {
    List<BookReviewReply> findByReviewIdInOrderByCreatedAtAsc(Collection<Long> reviewIds);
    Optional<BookReviewReply> findByIdAndReviewId(Long id, Long reviewId);
}
