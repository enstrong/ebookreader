package com.example.ebookreader.dto;

import java.util.ArrayList;
import java.util.List;

public class LookupTranslationDTO {
    private String source;
    private String text;
    private List<String> alternatives = new ArrayList<>();

    public LookupTranslationDTO() {
    }

    public LookupTranslationDTO(String source, String text, List<String> alternatives) {
        this.source = source;
        this.text = text;
        this.alternatives = alternatives == null ? new ArrayList<>() : alternatives;
    }

    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }

    public String getText() { return text; }
    public void setText(String text) { this.text = text; }

    public List<String> getAlternatives() { return alternatives; }
    public void setAlternatives(List<String> alternatives) {
        this.alternatives = alternatives == null ? new ArrayList<>() : alternatives;
    }
}
