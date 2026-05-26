package com.example.ebookreader.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class GoodreadsWorkService {

    private final Path workMapPath;
    private volatile WorkIndex cachedIndex;

    public GoodreadsWorkService(
            @Value("${recommendations.work-map-path:../data/recommendations/hybrid/goodreads_work_map.csv}") String workMapPath) {
        this.workMapPath = Path.of(workMapPath);
    }

    public String workIdFor(String goodreadsId) {
        if (goodreadsId == null || goodreadsId.isBlank()) {
            return null;
        }
        return index().workIdByGoodreadsId().get(goodreadsId);
    }

    public List<String> bookIdsForSameWork(String goodreadsId) {
        String workId = workIdFor(goodreadsId);
        if (workId == null || workId.isBlank()) {
            return List.of();
        }
        return index().goodreadsIdsByWorkId().getOrDefault(workId, List.of());
    }

    public void reload() {
        cachedIndex = null;
    }

    private WorkIndex index() {
        WorkIndex index = cachedIndex;
        if (index != null) {
            return index;
        }
        synchronized (this) {
            if (cachedIndex == null) {
                cachedIndex = loadIndex();
            }
            return cachedIndex;
        }
    }

    private WorkIndex loadIndex() {
        Map<String, String> workIdByGoodreadsId = new HashMap<>();
        Map<String, List<String>> goodreadsIdsByWorkId = new HashMap<>();
        Path path = resolveWorkMapPath();
        if (!Files.exists(path)) {
            return new WorkIndex(workIdByGoodreadsId, goodreadsIdsByWorkId);
        }

        try (BufferedReader reader = Files.newBufferedReader(path)) {
            String header = reader.readLine();
            if (header == null) {
                return new WorkIndex(workIdByGoodreadsId, goodreadsIdsByWorkId);
            }

            String line;
            while ((line = reader.readLine()) != null) {
                String[] columns = line.split(",", -1);
                if (columns.length < 2) {
                    continue;
                }
                String goodreadsId = columns[0].trim();
                String workId = columns[1].trim();
                if (goodreadsId.isBlank() || workId.isBlank()) {
                    continue;
                }
                workIdByGoodreadsId.put(goodreadsId, workId);
                goodreadsIdsByWorkId.computeIfAbsent(workId, ignored -> new ArrayList<>()).add(goodreadsId);
            }
        } catch (IOException ex) {
            return new WorkIndex(Map.of(), Map.of());
        }

        return new WorkIndex(workIdByGoodreadsId, goodreadsIdsByWorkId);
    }

    private Path resolveWorkMapPath() {
        if (Files.exists(workMapPath)) {
            return workMapPath;
        }
        Path repoRelative = Path.of("").toAbsolutePath().resolve(workMapPath).normalize();
        if (Files.exists(repoRelative)) {
            return repoRelative;
        }
        return workMapPath;
    }

    private record WorkIndex(
            Map<String, String> workIdByGoodreadsId,
            Map<String, List<String>> goodreadsIdsByWorkId) {
    }
}
