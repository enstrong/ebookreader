package com.example.ebookreader.service;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.example.ebookreader.dto.LookupDefinitionDTO;
import com.example.ebookreader.dto.LookupRequest;
import com.example.ebookreader.dto.LookupResponseDTO;
import com.example.ebookreader.dto.LookupTranslationDTO;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class LookupService {

    private static final int MAX_DEFINITIONS = 4;
    private static final int TRANSLATION_ALTERNATIVES = 3;

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final String translateBaseUrl;
    private final String translateApiKey;
    private final int providerTimeoutMs;

    public LookupService(
            ObjectMapper objectMapper,
            @Value("${lookup.translate-base-url:http://localhost:5000}") String translateBaseUrl,
            @Value("${lookup.translate-api-key:}") String translateApiKey,
            @Value("${lookup.provider-timeout-ms:5000}") int providerTimeoutMs) {
        this.objectMapper = objectMapper;
        this.translateBaseUrl = trimTrailingSlash(translateBaseUrl);
        this.translateApiKey = translateApiKey == null ? "" : translateApiKey.trim();
        this.providerTimeoutMs = providerTimeoutMs;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofMillis(providerTimeoutMs))
                .build();
    }

    public LookupResponseDTO lookup(LookupRequest request) {
        String normalized = normalizeSelection(request.getText());
        String detectedLanguage = detectLanguage(normalized, request.getSourceLanguage());
        String targetLanguage = chooseTargetLanguage(detectedLanguage, request.getTargetLanguage());

        LookupResponseDTO response = new LookupResponseDTO();
        response.setNormalizedText(normalized);
        response.setDetectedLanguage(detectedLanguage);
        response.setTargetLanguage(targetLanguage);

        if (!"en".equals(detectedLanguage) && !"ru".equals(detectedLanguage)) {
            response.getErrors().add("Поддерживаются только английский и русский языки");
            return response;
        }

        String dictionaryTerm = normalizeDictionaryTerm(normalized, detectedLanguage);
        if (isSingleWord(dictionaryTerm)) {
            try {
                response.setDefinitions(fetchDefinitions(dictionaryTerm, detectedLanguage));
            } catch (Exception ex) {
                response.getErrors().add("Не удалось загрузить определение");
            }
        }

        if ("en".equals(detectedLanguage)) {
            try {
                response.setTranslation(fetchTranslation(normalized, detectedLanguage, targetLanguage));
            } catch (Exception ex) {
                response.getErrors().add("Не удалось загрузить перевод");
            }
        }

        return response;
    }

    private List<LookupDefinitionDTO> fetchDefinitions(String word, String language) throws IOException, InterruptedException {
        if ("ru".equals(language)) {
            return fetchRussianDefinitions(word);
        }
        return fetchEnglishDefinitions(word);
    }

    private List<LookupDefinitionDTO> fetchEnglishDefinitions(String word) throws IOException, InterruptedException {
        for (String candidate : englishDictionaryCandidates(word)) {
            List<LookupDefinitionDTO> definitions = fetchEnglishDefinitionCandidate(candidate);
            if (!definitions.isEmpty()) {
                return definitions;
            }
        }
        return List.of();
    }

    private List<LookupDefinitionDTO> fetchEnglishDefinitionCandidate(String word) throws IOException, InterruptedException {
        String encodedWord = encode(word);
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create("https://api.dictionaryapi.dev/api/v2/entries/en/" + encodedWord))
                .timeout(Duration.ofMillis(providerTimeoutMs))
                .GET()
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            return List.of();
        }

        JsonNode root = objectMapper.readTree(response.body());
        if (!root.isArray()) {
            return List.of();
        }

        List<LookupDefinitionDTO> definitions = new ArrayList<>();
        for (JsonNode entry : root) {
            String entryWord = entry.path("word").asText(word);
            for (JsonNode meaning : entry.path("meanings")) {
                String partOfSpeech = meaning.path("partOfSpeech").asText("");
                for (JsonNode definition : meaning.path("definitions")) {
                    String text = definition.path("definition").asText("");
                    if (text.isBlank()) {
                        continue;
                    }
                    definitions.add(new LookupDefinitionDTO(
                            "dictionaryapi.dev",
                            entryWord,
                            partOfSpeech,
                            text,
                            definition.path("example").asText("")
                    ));
                    if (definitions.size() >= MAX_DEFINITIONS) {
                        return definitions;
                    }
                }
            }
        }
        return definitions;
    }

    private List<LookupDefinitionDTO> fetchRussianDefinitions(String word) throws IOException, InterruptedException {
        String title = encode(word.toLowerCase());
        String url = "https://ru.wiktionary.org/w/api.php"
                + "?action=query&format=json&prop=extracts&explaintext=1&exintro=1&redirects=1&titles=" + title;
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(url))
                .timeout(Duration.ofMillis(providerTimeoutMs))
                .header("User-Agent", "ebookreader-diploma/1.0")
                .GET()
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() != 200) {
            return List.of();
        }

        JsonNode pages = objectMapper.readTree(response.body()).path("query").path("pages");
        if (!pages.isObject()) {
            return List.of();
        }

        List<LookupDefinitionDTO> definitions = new ArrayList<>();
        pages.fields().forEachRemaining(entry -> {
            JsonNode page = entry.getValue();
            String extract = page.path("extract").asText("");
            for (String line : extract.split("\\R")) {
                String cleaned = cleanWiktionaryLine(line);
                if (!cleaned.isBlank()) {
                    definitions.add(new LookupDefinitionDTO(
                            "ru.wiktionary.org",
                            page.path("title").asText(word),
                            "",
                            cleaned,
                            ""
                    ));
                    break;
                }
            }
        });
        return definitions.size() > MAX_DEFINITIONS ? definitions.subList(0, MAX_DEFINITIONS) : definitions;
    }

    private LookupTranslationDTO fetchTranslation(String text, String source, String target) throws IOException, InterruptedException {
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("q", text);
        payload.put("source", source);
        payload.put("target", target);
        payload.put("format", "text");
        payload.put("alternatives", TRANSLATION_ALTERNATIVES);
        if (!translateApiKey.isBlank()) {
            payload.put("api_key", translateApiKey);
        }

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(translateBaseUrl + "/translate"))
                .timeout(Duration.ofMillis(providerTimeoutMs))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(objectMapper.writeValueAsString(payload)))
                .build();
        HttpResponse<String> response = send(request);
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new IOException("Translation provider returned " + response.statusCode());
        }

        JsonNode root = objectMapper.readTree(response.body());
        String translatedText = root.path("translatedText").asText("");
        if (translatedText.isBlank()) {
            Map<String, Object> map = objectMapper.readValue(
                    response.body(),
                    new TypeReference<Map<String, Object>>() {}
            );
            Object fallback = map.get("translatedText");
            translatedText = fallback == null ? "" : fallback.toString();
        }
        List<String> alternatives = translationAlternatives(root.path("alternatives"), translatedText);
        return translatedText.isBlank()
                ? null
                : new LookupTranslationDTO("libretranslate", translatedText, alternatives);
    }

    private List<String> translationAlternatives(JsonNode alternativesNode, String translatedText) {
        if (!alternativesNode.isArray()) {
            return List.of();
        }
        List<String> alternatives = new ArrayList<>();
        for (JsonNode alternative : alternativesNode) {
            String text = alternative.asText("").trim();
            if (!text.isBlank() && !text.equalsIgnoreCase(translatedText) && !alternatives.contains(text)) {
                alternatives.add(text);
            }
        }
        return alternatives;
    }

    private HttpResponse<String> send(HttpRequest request) throws IOException, InterruptedException {
        return httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
    }

    private String normalizeSelection(String text) {
        if (text == null) {
            return "";
        }
        return text.trim().replaceAll("\\s+", " ");
    }

    private String normalizeDictionaryTerm(String text, String language) {
        String normalized = text
                .trim()
                .replace('’', '\'')
                .replace('‘', '\'')
                .replaceAll("^[^\\p{L}'-]+|[^\\p{L}'-]+$", "");
        if ("en".equals(language)) {
            return normalized.toLowerCase();
        }
        return normalized;
    }

    private String detectLanguage(String text, String requestedLanguage) {
        if (requestedLanguage != null && ("en".equalsIgnoreCase(requestedLanguage) || "ru".equalsIgnoreCase(requestedLanguage))) {
            return requestedLanguage.toLowerCase();
        }
        boolean hasCyrillic = text.codePoints().anyMatch(codePoint -> Character.UnicodeScript.of(codePoint) == Character.UnicodeScript.CYRILLIC);
        boolean hasLatin = text.codePoints().anyMatch(codePoint -> Character.UnicodeScript.of(codePoint) == Character.UnicodeScript.LATIN);
        if (hasCyrillic && !hasLatin) {
            return "ru";
        }
        if (hasLatin && !hasCyrillic) {
            return "en";
        }
        return hasCyrillic ? "ru" : "en";
    }

    private String chooseTargetLanguage(String sourceLanguage, String requestedTarget) {
        if ("en".equalsIgnoreCase(requestedTarget) || "ru".equalsIgnoreCase(requestedTarget)) {
            return requestedTarget.toLowerCase();
        }
        return "ru".equals(sourceLanguage) ? "en" : "ru";
    }

    private boolean isSingleWord(String text) {
        return text.matches("[\\p{L}’'\\-]+");
    }

    private List<String> englishDictionaryCandidates(String word) {
        String normalized = normalizeDictionaryTerm(word, "en");
        List<String> candidates = new ArrayList<>();
        addCandidate(candidates, normalized);

        if (normalized.endsWith("'s") && normalized.length() > 2) {
            addCandidate(candidates, normalized.substring(0, normalized.length() - 2));
        }
        if (normalized.endsWith("'") && normalized.length() > 1) {
            addCandidate(candidates, normalized.substring(0, normalized.length() - 1));
        }

        List<String> snapshot = new ArrayList<>(candidates);
        for (String candidate : snapshot) {
            addEnglishPluralFallbacks(candidates, candidate);
        }

        return candidates;
    }

    private void addEnglishPluralFallbacks(List<String> candidates, String word) {
        if (word.length() <= 3) {
            return;
        }
        if (word.endsWith("ies") && word.length() > 4) {
            addCandidate(candidates, word.substring(0, word.length() - 3) + "y");
        }
        if (word.endsWith("ves") && word.length() > 4) {
            addCandidate(candidates, word.substring(0, word.length() - 3) + "f");
            addCandidate(candidates, word.substring(0, word.length() - 3) + "fe");
        }
        if (word.endsWith("es") && word.length() > 4) {
            addCandidate(candidates, word.substring(0, word.length() - 2));
        }
        if (word.endsWith("s") && !word.endsWith("ss") && word.length() > 3) {
            addCandidate(candidates, word.substring(0, word.length() - 1));
        }
    }

    private void addCandidate(List<String> candidates, String candidate) {
        if (candidate == null || candidate.isBlank()) {
            return;
        }
        if (!candidates.contains(candidate)) {
            candidates.add(candidate);
        }
    }

    private String cleanWiktionaryLine(String line) {
        String cleaned = line
                .replaceAll("^#+\\s*", "")
                .replaceAll("^[:*;]+\\s*", "")
                .trim();
        if (cleaned.length() < 8 || cleaned.startsWith("{{") || cleaned.startsWith("|")) {
            return "";
        }
        if (cleaned.matches("(?i).*(произношение|морфологические|семантические|родственные|этимология|фразеологизмы).*")) {
            return "";
        }
        return cleaned;
    }

    private String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    private String trimTrailingSlash(String value) {
        if (value == null || value.isBlank()) {
            return "http://localhost:5000";
        }
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }
}
