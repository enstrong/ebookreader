package com.example.ebookreader.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import com.example.ebookreader.model.AudioTrack;

@Repository
public interface AudioTrackRepository extends JpaRepository<AudioTrack, Long> {
    List<AudioTrack> findByBookIdOrderBySegmentOrderAsc(Long bookId);
    Optional<AudioTrack> findByIdAndBookId(Long id, Long bookId);
    long countByBookId(Long bookId);

    @Modifying
    @Transactional
    void deleteByBookId(Long bookId);
}
