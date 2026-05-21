package com.example.ebookreader.controller;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.model.User;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.service.RecommendationService;

@RestController
@RequestMapping("/api/recommendations")
@CrossOrigin(origins = "*")
public class RecommendationController {

    private final RecommendationService recommendationService;
    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;

    public RecommendationController(
            RecommendationService recommendationService,
            UserRepository userRepository,
            JwtUtil jwtUtil) {
        this.recommendationService = recommendationService;
        this.userRepository = userRepository;
        this.jwtUtil = jwtUtil;
    }

    @GetMapping("/me")
    public ResponseEntity<?> recommendForCurrentUser(
            @RequestHeader("Authorization") String token,
            @RequestParam(defaultValue = "20") int limit) {
        Optional<User> user = getUserFromToken(token);
        if (user.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        List<Map<String, Object>> recommendations = recommendationService.recommendForUser(
                user.get(),
                clampLimit(limit)
        );
        return ResponseEntity.ok(Map.of(
                "recommendations", recommendations,
                "sourceCount", recommendationService.positiveSourceCount(user.get())
        ));
    }

    @GetMapping("/books/{bookId}/similar")
    public ResponseEntity<?> similarBooks(
            @PathVariable Long bookId,
            @RequestParam(defaultValue = "20") int limit) {
        List<Map<String, Object>> similar = recommendationService.findSimilarBooks(bookId, clampLimit(limit));
        return ResponseEntity.ok(Map.of("similar", similar));
    }

    @PostMapping("/preview")
    public ResponseEntity<?> previewRecommendations(
            @RequestBody Map<String, Object> request,
            @RequestParam(defaultValue = "50") int limit) {
        Object rawInteractions = request.get("interactions");
        if (!(rawInteractions instanceof List<?> rawList)) {
            return ResponseEntity.badRequest().body(Map.of("message", "interactions is required"));
        }

        List<Map<String, Object>> interactions = rawList.stream()
                .filter(Map.class::isInstance)
                .map(Map.class::cast)
                .map(row -> (Map<String, Object>) row)
                .toList();
        List<Map<String, Object>> recommendations = recommendationService.previewRecommendations(
                interactions,
                clampLimit(limit)
        );
        return ResponseEntity.ok(Map.of(
                "recommendations", recommendations,
                "sourceCount", interactions.size()
        ));
    }

    @PostMapping("/refresh")
    public ResponseEntity<?> refresh() {
        recommendationService.reload();
        return ResponseEntity.ok(Map.of("message", "Recommendation similarities reloaded"));
    }

    private Optional<User> getUserFromToken(String token) {
        try {
            String username = jwtUtil.extractUsername(token.replace("Bearer ", ""));
            return userRepository.findByNickname(username);
        } catch (Exception ex) {
            return Optional.empty();
        }
    }

    private int clampLimit(int limit) {
        if (limit < 1) {
            return 1;
        }
        return Math.min(limit, 100);
    }
}
