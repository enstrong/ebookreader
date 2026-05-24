package com.example.ebookreader.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Pattern;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

@Service
public class GoodreadsAuthorNameService {

    private static final Pattern NUMERIC_AUTHOR_LIST = Pattern.compile("^[\\d,\\s|]+$");
    private static final Pattern AUTHOR_ID_SEPARATOR = Pattern.compile("[,|\\s]+");

    private final Map<String, String> namesById;
    private final Map<String, String> authorIdsByGoodreadsBookId;

    public GoodreadsAuthorNameService() {
        this.namesById = loadAuthorNames();
        this.authorIdsByGoodreadsBookId = loadBookAuthorIds();
    }

    public Optional<String> resolveAuthorNames(String rawAuthor) {
        if (rawAuthor == null || rawAuthor.isBlank()) {
            return Optional.empty();
        }
        String trimmed = rawAuthor.trim();
        if (!NUMERIC_AUTHOR_LIST.matcher(trimmed).matches()) {
            return Optional.of(trimmed);
        }

        Set<String> names = new LinkedHashSet<>();
        for (String authorId : AUTHOR_ID_SEPARATOR.split(trimmed)) {
            if (authorId.isBlank()) {
                continue;
            }
            String name = namesById.get(authorId.trim());
            if (name != null && !name.isBlank()) {
                names.add(name);
            }
        }

        if (names.isEmpty()) {
            return Optional.empty();
        }
        return Optional.of(String.join(", ", names));
    }

    public Optional<String> resolveAuthorNamesForBook(String goodreadsBookId) {
        if (goodreadsBookId == null || goodreadsBookId.isBlank()) {
            return Optional.empty();
        }
        String authorIds = authorIdsByGoodreadsBookId.get(goodreadsBookId.trim());
        return resolveAuthorNames(authorIds);
    }

    public boolean isNumericAuthorList(String rawAuthor) {
        return rawAuthor != null && NUMERIC_AUTHOR_LIST.matcher(rawAuthor.trim()).matches();
    }

    private Map<String, String> loadAuthorNames() {
        ClassPathResource resource = new ClassPathResource("data/goodreads_author_names.csv");
        Map<String, String> result = new HashMap<>();
        if (!resource.exists()) {
            return result;
        }

        try (InputStream stream = resource.getInputStream();
             BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line = reader.readLine();
            while ((line = reader.readLine()) != null) {
                List<String> columns = parseCsvLine(line);
                if (columns.size() < 2) {
                    continue;
                }
                String authorId = columns.get(0).trim();
                String name = columns.get(1).trim();
                if (!authorId.isBlank() && !name.isBlank()) {
                    result.put(authorId, name);
                }
            }
        } catch (IOException ignored) {
            return Map.of();
        }
        return Map.copyOf(result);
    }

    private Map<String, String> loadBookAuthorIds() {
        ClassPathResource resource = new ClassPathResource("data/goodreads_book_author_ids.csv");
        Map<String, String> result = new HashMap<>();
        if (!resource.exists()) {
            return result;
        }

        try (InputStream stream = resource.getInputStream();
             BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line = reader.readLine();
            while ((line = reader.readLine()) != null) {
                List<String> columns = parseCsvLine(line);
                if (columns.size() < 2) {
                    continue;
                }
                String goodreadsBookId = columns.get(0).trim();
                String authorIds = columns.get(1).trim();
                if (!goodreadsBookId.isBlank() && !authorIds.isBlank()) {
                    result.put(goodreadsBookId, authorIds);
                }
            }
        } catch (IOException ignored) {
            return Map.of();
        }
        return Map.copyOf(result);
    }

    private List<String> parseCsvLine(String line) {
        List<String> values = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean quoted = false;

        for (int i = 0; i < line.length(); i++) {
            char ch = line.charAt(i);
            if (ch == '"') {
                if (quoted && i + 1 < line.length() && line.charAt(i + 1) == '"') {
                    current.append('"');
                    i++;
                } else {
                    quoted = !quoted;
                }
            } else if (ch == ',' && !quoted) {
                values.add(current.toString());
                current.setLength(0);
            } else {
                current.append(ch);
            }
        }
        values.add(current.toString());
        return values;
    }
}
