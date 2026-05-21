package com.example.ebookreader.dto;

public class LookupRequest {
    private String text;
    private String sourceLanguage = "auto";
    private String targetLanguage;

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }

    public String getSourceLanguage() { return sourceLanguage; }
    public void setSourceLanguage(String sourceLanguage) { this.sourceLanguage = sourceLanguage; }

    public String getTargetLanguage() { return targetLanguage; }
    public void setTargetLanguage(String targetLanguage) { this.targetLanguage = targetLanguage; }
}
