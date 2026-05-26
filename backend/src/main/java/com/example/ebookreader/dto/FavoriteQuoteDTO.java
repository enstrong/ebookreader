package com.example.ebookreader.dto;

import java.time.LocalDateTime;

public class FavoriteQuoteDTO {
    private Long id;
    private Long bookId;
    private String bookTitle;
    private String bookAuthor;
    private String text;
    private Integer chapterOrder;
    private String nickname;
    private String avatarInitial;
    private int likes;
    private int dislikes;
    private int currentUserVote;
    private boolean currentUserQuote;
    private LocalDateTime publishedAt;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getBookId() { return bookId; }
    public void setBookId(Long bookId) { this.bookId = bookId; }

    public String getBookTitle() { return bookTitle; }
    public void setBookTitle(String bookTitle) { this.bookTitle = bookTitle; }

    public String getBookAuthor() { return bookAuthor; }
    public void setBookAuthor(String bookAuthor) { this.bookAuthor = bookAuthor; }

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }

    public Integer getChapterOrder() { return chapterOrder; }
    public void setChapterOrder(Integer chapterOrder) { this.chapterOrder = chapterOrder; }

    public String getNickname() { return nickname; }
    public void setNickname(String nickname) { this.nickname = nickname; }

    public String getAvatarInitial() { return avatarInitial; }
    public void setAvatarInitial(String avatarInitial) { this.avatarInitial = avatarInitial; }

    public int getLikes() { return likes; }
    public void setLikes(int likes) { this.likes = likes; }

    public int getDislikes() { return dislikes; }
    public void setDislikes(int dislikes) { this.dislikes = dislikes; }

    public int getCurrentUserVote() { return currentUserVote; }
    public void setCurrentUserVote(int currentUserVote) { this.currentUserVote = currentUserVote; }

    public boolean isCurrentUserQuote() { return currentUserQuote; }
    public void setCurrentUserQuote(boolean currentUserQuote) { this.currentUserQuote = currentUserQuote; }

    public LocalDateTime getPublishedAt() { return publishedAt; }
    public void setPublishedAt(LocalDateTime publishedAt) { this.publishedAt = publishedAt; }
}
