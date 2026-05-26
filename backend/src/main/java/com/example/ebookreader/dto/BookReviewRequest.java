package com.example.ebookreader.dto;

public class BookReviewRequest {
    private Integer rating;
    private String text;
    private Long parentReplyId;
    private Integer vote;

    public Integer getRating() { return rating; }
    public void setRating(Integer rating) { this.rating = rating; }

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }

    public Long getParentReplyId() { return parentReplyId; }
    public void setParentReplyId(Long parentReplyId) { this.parentReplyId = parentReplyId; }

    public Integer getVote() { return vote; }
    public void setVote(Integer vote) { this.vote = vote; }
}
