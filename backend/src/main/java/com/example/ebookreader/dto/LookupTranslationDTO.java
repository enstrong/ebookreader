package com.example.ebookreader.dto;

public class LookupTranslationDTO {
    private String source;
    private String text;

    public LookupTranslationDTO() {
    }

    public LookupTranslationDTO(String source, String text) {
        this.source = source;
        this.text = text;
    }

    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }
}
