package com.example.ebookreader.dto;

import java.time.LocalDateTime;

import com.example.ebookreader.model.BookAnnotation;

public class BookAnnotationDTO {
    private Long id;
    private Long bookId;
    private Integer chapterOrder;
    private Integer startOffset;
    private Integer endOffset;
    private String highlightedText;
    private String note;
    private String color;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public static BookAnnotationDTO fromEntity(BookAnnotation annotation) {
        BookAnnotationDTO dto = new BookAnnotationDTO();
        dto.setId(annotation.getId());
        dto.setBookId(annotation.getBook().getId());
        dto.setChapterOrder(annotation.getChapterOrder());
        dto.setStartOffset(annotation.getStartOffset());
        dto.setEndOffset(annotation.getEndOffset());
        dto.setHighlightedText(annotation.getHighlightedText());
        dto.setNote(annotation.getNote());
        dto.setColor(annotation.getColor());
        dto.setCreatedAt(annotation.getCreatedAt());
        dto.setUpdatedAt(annotation.getUpdatedAt());
        return dto;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getBookId() { return bookId; }
    public void setBookId(Long bookId) { this.bookId = bookId; }

    public Integer getChapterOrder() { return chapterOrder; }
    public void setChapterOrder(Integer chapterOrder) { this.chapterOrder = chapterOrder; }

    public Integer getStartOffset() { return startOffset; }
    public void setStartOffset(Integer startOffset) { this.startOffset = startOffset; }

    public Integer getEndOffset() { return endOffset; }
    public void setEndOffset(Integer endOffset) { this.endOffset = endOffset; }

    public String getHighlightedText() { return highlightedText; }
    public void setHighlightedText(String highlightedText) { this.highlightedText = highlightedText; }

    public String getNote() { return note; }
    public void setNote(String note) { this.note = note; }

    public String getColor() { return color; }
    public void setColor(String color) { this.color = color; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public LocalDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(LocalDateTime updatedAt) { this.updatedAt = updatedAt; }
}
