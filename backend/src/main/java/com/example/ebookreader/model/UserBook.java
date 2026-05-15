package com.example.ebookreader.model;

import java.time.LocalDateTime;

import com.fasterxml.jackson.annotation.JsonBackReference;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "user_books")
public class UserBook {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "user_id", nullable = false)
    @JsonBackReference // ❗ предотвращает бесконечную рекурсию user → userBooks → user
    private User user;

    @ManyToOne
    @JoinColumn(name = "book_id", nullable = false)
    private Book book;

    @Column(nullable = false)
    private Integer currentChapter = 1;

    @Column
    private Integer segmentOrder = 1;

    @Column
    private Double segmentProgress = 0.0;

    @Column
    private Long audioPositionMs = 0L;

    @Enumerated(EnumType.STRING)
    @Column
    private ProgressMode lastMode = ProgressMode.TEXT;

    @Column(nullable = false)
    private boolean bookmarked = false;

    @Enumerated(EnumType.STRING)
    @Column
    private ReadingStatus status = ReadingStatus.WANT_TO_READ;

    @Column
    private Integer rating;

    @Column
    private LocalDateTime startedAt;

    @Column
    private LocalDateTime finishedAt;

    @Column
    private LocalDateTime lastReadAt;

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Book getBook() {
        return book;
    }

    public void setBook(Book book) {
        this.book = book;
    }

    public Integer getCurrentChapter() {
        if (currentChapter == null) {
            return getSegmentOrder();
        }
        return currentChapter;
    }

    public void setCurrentChapter(Integer currentChapter) {
        this.currentChapter = currentChapter == null ? 1 : currentChapter;
        this.segmentOrder = this.currentChapter;
    }

    public Integer getSegmentOrder() {
        if (segmentOrder == null) {
            return currentChapter == null ? 1 : currentChapter;
        }
        return segmentOrder;
    }

    public void setSegmentOrder(Integer segmentOrder) {
        this.segmentOrder = segmentOrder == null ? 1 : segmentOrder;
        this.currentChapter = this.segmentOrder;
    }

    public Double getSegmentProgress() {
        if (segmentProgress == null) {
            return 0.0;
        }
        return segmentProgress;
    }

    public void setSegmentProgress(Double segmentProgress) {
        if (segmentProgress == null) {
            this.segmentProgress = 0.0;
            return;
        }
        this.segmentProgress = Math.max(0.0, Math.min(1.0, segmentProgress));
    }

    public Long getAudioPositionMs() {
        if (audioPositionMs == null) {
            return 0L;
        }
        return audioPositionMs;
    }

    public void setAudioPositionMs(Long audioPositionMs) {
        this.audioPositionMs = audioPositionMs == null ? 0L : Math.max(0L, audioPositionMs);
    }

    public ProgressMode getLastMode() {
        if (lastMode == null) {
            return ProgressMode.TEXT;
        }
        return lastMode;
    }

    public void setLastMode(ProgressMode lastMode) {
        this.lastMode = lastMode == null ? ProgressMode.TEXT : lastMode;
    }

    public boolean isBookmarked() {
        return bookmarked;
    }

    public void setBookmarked(boolean bookmarked) {
        this.bookmarked = bookmarked;
    }

    public ReadingStatus getStatus() {
        if (status == null) {
            return ReadingStatus.WANT_TO_READ;
        }
        return status;
    }

    public void setStatus(ReadingStatus status) {
        this.status = status == null ? ReadingStatus.WANT_TO_READ : status;
    }

    public Integer getRating() {
        return rating;
    }

    public void setRating(Integer rating) {
        this.rating = rating;
    }

    public LocalDateTime getStartedAt() {
        return startedAt;
    }

    public void setStartedAt(LocalDateTime startedAt) {
        this.startedAt = startedAt;
    }

    public LocalDateTime getFinishedAt() {
        return finishedAt;
    }

    public void setFinishedAt(LocalDateTime finishedAt) {
        this.finishedAt = finishedAt;
    }

    public LocalDateTime getLastReadAt() {
        return lastReadAt;
    }

    public void setLastReadAt(LocalDateTime lastReadAt) {
        this.lastReadAt = lastReadAt;
    }
}
