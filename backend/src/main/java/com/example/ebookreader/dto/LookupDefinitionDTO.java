package com.example.ebookreader.dto;

public class LookupDefinitionDTO {
    private String source;
    private String word;
    private String partOfSpeech;
    private String definition;
    private String example;

    public LookupDefinitionDTO() {
    }

    public LookupDefinitionDTO(String source, String word, String partOfSpeech, String definition, String example) {
        this.source = source;
        this.word = word;
        this.partOfSpeech = partOfSpeech;
        this.definition = definition;
        this.example = example;
    }

    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }

    public String getWord() { return word; }
    public void setWord(String word) { this.word = word; }

    public String getPartOfSpeech() { return partOfSpeech; }
    public void setPartOfSpeech(String partOfSpeech) { this.partOfSpeech = partOfSpeech; }

    public String getDefinition() { return definition; }
    public void setDefinition(String definition) { this.definition = definition; }

    public String getExample() { return example; }
    public void setExample(String example) { this.example = example; }
}
