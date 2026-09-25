package com.example.ebookreader.model;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonIgnore;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String nickname;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String password;

    @Column(nullable = false)
    private String role = "USER";

    @Column(name = "google_subject", unique = true)
    private String googleSubject;

    @Column(name = "auth_provider")
    private String authProvider = "LOCAL";

    // 🔹 Добавлено: связь с user_books
    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
    @JsonIgnore // ❗ предотвращает рекурсивную сериализацию
    private List<UserBook> userBooks;

    @Column(name = "demo_expires_at")
    private java.time.Instant demoExpiresAt;

    public java.time.Instant getDemoExpiresAt() { return demoExpiresAt; }
    public void setDemoExpiresAt(java.time.Instant value) { demoExpiresAt = value; }

    // Constructors
    public User() {}

    public User(String nickname, String email, String password, String role) {
        this.nickname = nickname;
        this.email = email;
        this.password = password;
        this.role = role;
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public String getGoogleSubject() {
        return googleSubject;
    }

    public void setGoogleSubject(String googleSubject) {
        this.googleSubject = googleSubject;
    }

    public String getAuthProvider() {
        return authProvider;
    }

    public void setAuthProvider(String authProvider) {
        this.authProvider = authProvider;
    }

    public List<UserBook> getUserBooks() {
        return userBooks;
    }

    public void setUserBooks(List<UserBook> userBooks) {
        this.userBooks = userBooks;
    }
}
