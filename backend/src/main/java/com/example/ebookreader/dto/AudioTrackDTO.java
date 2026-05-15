package com.example.ebookreader.dto;

public class AudioTrackDTO {
    private Long id;
    private Integer segmentOrder;
    private String title;
    private Long durationMs;
    private String streamUrl;
    private String contentType;

    public AudioTrackDTO() {
    }

    public AudioTrackDTO(Long id, Integer segmentOrder, String title, Long durationMs, String streamUrl, String contentType) {
        this.id = id;
        this.segmentOrder = segmentOrder;
        this.title = title;
        this.durationMs = durationMs;
        this.streamUrl = streamUrl;
        this.contentType = contentType;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Integer getSegmentOrder() { return segmentOrder; }
    public void setSegmentOrder(Integer segmentOrder) { this.segmentOrder = segmentOrder; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public Long getDurationMs() { return durationMs; }
    public void setDurationMs(Long durationMs) { this.durationMs = durationMs; }

    public String getStreamUrl() { return streamUrl; }
    public void setStreamUrl(String streamUrl) { this.streamUrl = streamUrl; }

    public String getContentType() { return contentType; }
    public void setContentType(String contentType) { this.contentType = contentType; }
}
