package com.example.ebookreader.dto;

public class BookAnnotationRequest {
    private Integer chapterOrder;
    private Integer startOffset;
    private Integer endOffset;
    private String highlightedText;
    private String note;
    private String color;

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
}
