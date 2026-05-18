package com.example.ebookreader.model;

import java.util.HashSet;
import java.util.Set;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.JoinTable;
import jakarta.persistence.ManyToMany;
import jakarta.persistence.Table;

@Entity
@Table(name = "books")
public class Book {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 1000)
    private String title;

    @Column(length = 1000)
    private String author;

    @Column(length = 2000)
    private String description;

    @Column(length = 1000)
    private String coverUrl;

    @ManyToMany(cascade = {CascadeType.PERSIST, CascadeType.MERGE}, fetch = FetchType.LAZY)
    @JoinTable(
        name = "book_genres",
        joinColumns = @JoinColumn(name = "book_id"),
        inverseJoinColumns = @JoinColumn(name = "genre_id")
    )
    private Set<Genre> genres = new HashSet<>();

    @Column(unique = true)
    private String goodreadsId;

    @Column
    private Double averageRating;

    @Column
    private Integer ratingsCount;

    @Column
    private Integer reviewCount;

    @Column(length = 1000)
    private String externalUrl;

    @Column(name = "language", length = 64)
    private String languageCode;

    @Column(name = "page_count")
    private Integer pageCount;

    @Enumerated(EnumType.STRING)
    @Column
    private BookAvailability availability = BookAvailability.METADATA_ONLY;

    // Getters and Setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getAuthor() { return author; }
    public void setAuthor(String author) { this.author = author; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getCoverUrl() { return coverUrl; }
    public void setCoverUrl(String coverUrl) { this.coverUrl = coverUrl; }

    public Set<Genre> getGenres() { return genres; }
    public void setGenres(Set<Genre> genres) { this.genres = genres; }

    public String getGoodreadsId() { return goodreadsId; }
    public void setGoodreadsId(String goodreadsId) { this.goodreadsId = goodreadsId; }

    public Double getAverageRating() { return averageRating; }
    public void setAverageRating(Double averageRating) { this.averageRating = averageRating; }

    public Integer getRatingsCount() { return ratingsCount; }
    public void setRatingsCount(Integer ratingsCount) { this.ratingsCount = ratingsCount; }

    public Integer getReviewCount() { return reviewCount; }
    public void setReviewCount(Integer reviewCount) { this.reviewCount = reviewCount; }

    public String getExternalUrl() { return externalUrl; }
    public void setExternalUrl(String externalUrl) { this.externalUrl = externalUrl; }

    @JsonProperty("language")
    @JsonAlias({"languageCode", "language_code"})
    public String getLanguageCode() { return languageCode; }

    @JsonProperty("language")
    @JsonAlias({"languageCode", "language_code"})
    public void setLanguageCode(String languageCode) { this.languageCode = languageCode; }

    public Integer getPageCount() { return pageCount; }
    public void setPageCount(Integer pageCount) { this.pageCount = pageCount; }

    public BookAvailability getAvailability() {
        if (availability == null) {
            return BookAvailability.METADATA_ONLY;
        }
        return availability;
    }

    public void setAvailability(BookAvailability availability) {
        this.availability = availability == null ? BookAvailability.METADATA_ONLY : availability;
    }

    public boolean isReadable() {
        return getAvailability().hasText();
    }

    public boolean isListenable() {
        return getAvailability().hasAudio();
    }
}
