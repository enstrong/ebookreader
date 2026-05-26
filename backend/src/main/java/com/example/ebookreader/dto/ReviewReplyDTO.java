package com.example.ebookreader.dto;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

public class ReviewReplyDTO {
    private Long id;
    private String text;
    private String nickname;
    private String avatarInitial;
    private int likes;
    private int dislikes;
    private int currentUserVote;
    private LocalDateTime createdAt;
    private List<ReviewReplyDTO> replies = new ArrayList<>();

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }

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

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }

    public List<ReviewReplyDTO> getReplies() { return replies; }
    public void setReplies(List<ReviewReplyDTO> replies) { this.replies = replies; }
}
