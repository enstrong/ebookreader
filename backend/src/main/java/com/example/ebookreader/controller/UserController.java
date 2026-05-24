package com.example.ebookreader.controller;

import java.util.HashMap;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.model.User;
import com.example.ebookreader.repository.UserRepository;

@RestController
@RequestMapping("/api/user")
@CrossOrigin(origins = "*")
public class UserController {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private JwtUtil jwtUtil;

    @Autowired
    private UserDetailsService userDetailsService;

    @GetMapping("/profile")
    public ResponseEntity<?> getProfile(@RequestHeader("Authorization") String token) {
        String identifier = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        
        User user = userRepository.findByNickname(identifier)
                .orElseGet(() -> userRepository.findByEmail(identifier).orElse(null));
        
        if (user == null) {
            return ResponseEntity.notFound().build();
        }
        
        Map<String, Object> profile = new HashMap<>();
        profile.put("username", user.getNickname());
        profile.put("email", user.getEmail());
        profile.put("nickname", user.getNickname());
        profile.put("role", user.getRole());
        profile.put("authProvider", user.getAuthProvider());
        profile.put("audioSubscriptionActive", user.isAudioSubscriptionActive());
        return ResponseEntity.ok(profile);
    }

    @PutMapping("/audio-subscription")
    public ResponseEntity<?> updateAudioSubscription(
            @RequestHeader("Authorization") String token,
            @RequestBody Map<String, Boolean> request) {
        String identifier = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        User user = userRepository.findByNickname(identifier)
                .orElseGet(() -> userRepository.findByEmail(identifier).orElse(null));

        if (user == null) {
            return ResponseEntity.notFound().build();
        }

        boolean active = Boolean.TRUE.equals(request.get("active"));
        user.setAudioSubscriptionActive(active);
        userRepository.save(user);

        return ResponseEntity.ok(Map.of(
                "message", active ? "Подписка на аудиокниги активирована" : "Подписка на аудиокниги отключена",
                "audioSubscriptionActive", user.isAudioSubscriptionActive()
        ));
    }

    @PutMapping("/nickname")
    public ResponseEntity<?> updateNickname(
            @RequestHeader("Authorization") String token,
            @RequestBody Map<String, String> request) {
        String identifier = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        String nickname = request.get("nickname");
        
        if (nickname == null || nickname.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Никнейм не может быть пустым"));
        }

        User user = userRepository.findByNickname(identifier)
                .orElseGet(() -> userRepository.findByEmail(identifier).orElse(null));
        
        if (user == null) {
            return ResponseEntity.notFound().build();
        }

        // Проверка, занят ли никнейм
        if (userRepository.findByNickname(nickname).isPresent()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Никнейм уже занят"));
        }
        
        user.setNickname(nickname);
        userRepository.save(user);

        // ✅ Генерируем новый токен с обновленным nickname
        UserDetails userDetails = userDetailsService.loadUserByUsername(user.getNickname());
        String newToken = jwtUtil.generateToken(user.getId(), userDetails);

        Map<String, Object> response = new HashMap<>();
        response.put("message", "Никнейм успешно обновлён");
        response.put("token", newToken); // ← Новый токен
        response.put("nickname", user.getNickname());
        
        return ResponseEntity.ok(response);
    }

    @PutMapping("/password")
    public ResponseEntity<?> changePassword(
            @RequestHeader("Authorization") String token,
            @RequestBody Map<String, String> request) {
        String identifier = jwtUtil.extractUsername(token.replace("Bearer ", ""));
        String oldPassword = request.get("oldPassword");
        String newPassword = request.get("newPassword");
        
        if (newPassword == null || newPassword.length() < 8) {
            return ResponseEntity.badRequest().body(
                Map.of("message", "Пароль должен содержать минимум 8 символов")
            );
        }

        User user = userRepository.findByNickname(identifier)
                .orElseGet(() -> userRepository.findByEmail(identifier).orElse(null));
        
        if (user == null) {
            return ResponseEntity.notFound().build();
        }

        if ("GOOGLE".equalsIgnoreCase(user.getAuthProvider())) {
            return ResponseEntity.badRequest().body(
                Map.of("message", "Пароль нельзя изменить для аккаунта Google")
            );
        }
        
        if (!passwordEncoder.matches(oldPassword, user.getPassword())) {
            return ResponseEntity.badRequest().body(
                Map.of("message", "Неверный старый пароль")
            );
        }
        
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
        
        return ResponseEntity.ok(Map.of("message", "Пароль успешно изменён"));
    }
}
