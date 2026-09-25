package com.example.ebookreader.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;

@Entity
@Table(name = "demo_uploads")
public class DemoUpload {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY) private Long id;
    @Column(nullable = false) private Long ownerId;
    @Column(nullable = false) private Long bookId;
    @Column(nullable = false) private String filename;
    @JsonIgnore @Column(nullable = false) private byte[] content;
    public void setOwnerId(Long value) { ownerId=value; }
    public void setBookId(Long value) { bookId=value; }
    public void setFilename(String value) { filename=value; }
    public void setContent(byte[] value) { content=value; }
}
