package com.example.ebookreader.dto;

import java.util.ArrayList;
import java.util.List;

public class LookupResponseDTO {
    private String normalizedText;
    private String detectedLanguage;
    private String targetLanguage;
    private List<LookupDefinitionDTO> definitions = new ArrayList<>();
    private LookupTranslationDTO translation;
    private List<String> errors = new ArrayList<>();

    public String getNormalizedText() { return normalizedText; }
    public void setNormalizedText(String normalizedText) { this.normalizedText = normalizedText; }

    public String getDetectedLanguage() { return detectedLanguage; }
    public void setDetectedLanguage(String detectedLanguage) { this.detectedLanguage = detectedLanguage; }

    public String getTargetLanguage() { return targetLanguage; }
    public void setTargetLanguage(String targetLanguage) { this.targetLanguage = targetLanguage; }

    public List<LookupDefinitionDTO> getDefinitions() { return definitions; }
    public void setDefinitions(List<LookupDefinitionDTO> definitions) { this.definitions = definitions; }

    public LookupTranslationDTO getTranslation() { return translation; }
    public void setTranslation(LookupTranslationDTO translation) { this.translation = translation; }

    public List<String> getErrors() { return errors; }
    public void setErrors(List<String> errors) { this.errors = errors; }
}
