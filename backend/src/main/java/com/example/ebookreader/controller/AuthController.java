package com.example.ebookreader.controller;

import java.util.Collections;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.dto.GoogleAuthRequest;
import com.example.ebookreader.dto.LoginRequest;
import com.example.ebookreader.dto.RegisterRequest;
import com.example.ebookreader.exception.BadRequestException;
import com.example.ebookreader.exception.UnauthorizedException;
import com.example.ebookreader.model.User;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.service.google.GoogleAccount;
import com.example.ebookreader.service.google.GoogleTokenVerifier;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/auth")
@CrossOrigin(origins = "*")
@Tag(name = "Аутентификация", description = "API для регистрации и входа пользователей")
public class AuthController {

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private JwtUtil jwtUtil;

    @Autowired
    private GoogleTokenVerifier googleTokenVerifier;

    @Operation(summary = "Регистрация нового пользователя")
    @PostMapping("/register")
    public ResponseEntity<?> register(@Valid @RequestBody RegisterRequest request) {
        try {
            String username = request.getUsername().trim();
            String email = request.getEmail().trim();

            if (userRepository.findByNickname(username).isPresent()) {
                throw new BadRequestException("Пользователь с таким именем уже существует");
            }

            if (userRepository.findByEmail(email).isPresent()) {
                throw new BadRequestException("Email уже используется");
            }

            User user = new User();
            user.setNickname(username);
            user.setEmail(email);
            user.setPassword(passwordEncoder.encode(request.getPassword()));
            user.setRole("USER");

            User savedUser = userRepository.save(user);

            // Создаем UserDetails напрямую для генерации токена
            UserDetails userDetails = new org.springframework.security.core.userdetails.User(
                    savedUser.getNickname(),
                    savedUser.getPassword(),
                    Collections.singletonList(new SimpleGrantedAuthority("ROLE_" + savedUser.getRole()))
            );

            String token = jwtUtil.generateToken(savedUser.getId(), userDetails);

            return ResponseEntity.ok(buildAuthResponse(savedUser, token, true));
            
        } catch (BadRequestException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .body(Map.of("message", "Ошибка регистрации: " + e.getMessage()));
        }
    }

    @Operation(summary = "Вход пользователя в систему")
    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request) {
        try {
            String loginIdentifier = request.getUsername().trim();
            String password = request.getPassword();

            // 1. Ищем пользователя по нику или почте
            User user = userRepository.findByNickname(loginIdentifier)
                    .orElseGet(() -> userRepository.findByEmail(loginIdentifier)
                    .orElseThrow(() -> new UnauthorizedException("Неверное имя пользователя или пароль")));

            // 2. Проверяем пароль через BCrypt
            if (!passwordEncoder.matches(password, user.getPassword())) {
                throw new UnauthorizedException("Неверное имя пользователя или пароль");
            }

            // 3. Создаем UserDetails вручную (без повторного запроса к БД)
            UserDetails userDetails = new org.springframework.security.core.userdetails.User(
                    user.getNickname(),
                    user.getPassword(),
                    Collections.singletonList(new SimpleGrantedAuthority("ROLE_" + user.getRole()))
            );

            // 4. Генерируем токен
            String token = jwtUtil.generateToken(user.getId(), userDetails);

            return ResponseEntity.ok(buildAuthResponse(user, token, false));
            
        } catch (UnauthorizedException e) {
            return ResponseEntity.status(401).body(Map.of("message", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .body(Map.of("message", "Ошибка входа: " + e.getMessage()));
        }
    }

    @Operation(summary = "Вход или регистрация через Google")
    @PostMapping("/google")
    public ResponseEntity<?> googleAuth(@Valid @RequestBody GoogleAuthRequest request) {
        try {
            GoogleAccount googleAccount = googleTokenVerifier.verify(request.getIdToken());

            boolean isNewUser = false;
            User user = userRepository.findByGoogleSubject(googleAccount.subject())
                    .orElseGet(() -> userRepository.findByEmailIgnoreCase(googleAccount.email()).orElse(null));

            if (user == null) {
                isNewUser = true;
                user = new User();
                user.setNickname(generateUniqueNickname(googleAccount));
                user.setEmail(googleAccount.email());
                user.setPassword(passwordEncoder.encode("GOOGLE_AUTH_" + UUID.randomUUID()));
                user.setRole("USER");
            }

            if (user.getGoogleSubject() != null
                    && !user.getGoogleSubject().isBlank()
                    && !user.getGoogleSubject().equals(googleAccount.subject())) {
                throw new BadRequestException("Email уже привязан к другому Google аккаунту");
            }

            if (user.getGoogleSubject() == null || user.getGoogleSubject().isBlank()) {
                user.setGoogleSubject(googleAccount.subject());
            }
            user.setAuthProvider("GOOGLE");

            User savedUser = userRepository.save(user);
            String token = jwtUtil.generateToken(savedUser.getId(), createUserDetails(savedUser));

            return ResponseEntity.ok(buildAuthResponse(savedUser, token, isNewUser));
        } catch (BadRequestException e) {
            return ResponseEntity.badRequest().body(Map.of("message", e.getMessage()));
        } catch (UnauthorizedException e) {
            return ResponseEntity.status(401).body(Map.of("message", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(500)
                    .body(Map.of("message", "Ошибка входа через Google: " + e.getMessage()));
        }
    }

    @Operation(summary = "Обновление токена")
    @PostMapping("/refresh")
    public ResponseEntity<?> refreshToken(@RequestHeader("Authorization") String authHeader) {
        try {
            String token = authHeader.replace("Bearer ", "");
            String identifier = jwtUtil.extractUsername(token);
            
            User user = userRepository.findByNickname(identifier)
                    .orElseGet(() -> userRepository.findByEmail(identifier)
                    .orElseThrow(() -> new UnauthorizedException("Пользователь не найден")));
            
            UserDetails userDetails = new org.springframework.security.core.userdetails.User(
                    user.getNickname(),
                    user.getPassword(),
                    Collections.singletonList(new SimpleGrantedAuthority("ROLE_" + user.getRole()))
            );

            String newToken = jwtUtil.generateToken(user.getId(), userDetails);
            
            Map<String, Object> response = new HashMap<>();
            response.put("token", newToken);
            response.put("username", user.getNickname());
            response.put("role", user.getRole());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(Map.of("message", "Ошибка обновления токена: " + e.getMessage()));
        }
    }

    @Operation(summary = "Тестовый эндпоинт")
    @GetMapping("/test")
    public ResponseEntity<?> test() {
        return ResponseEntity.ok(Map.of("message", "Auth controller is working"));
    }

    private UserDetails createUserDetails(User user) {
        return new org.springframework.security.core.userdetails.User(
                user.getNickname(),
                user.getPassword(),
                Collections.singletonList(new SimpleGrantedAuthority("ROLE_" + user.getRole()))
        );
    }

    private Map<String, Object> buildAuthResponse(User user, String token, boolean isNewUser) {
        Map<String, Object> response = new HashMap<>();
        response.put("token", token);
        response.put("username", user.getNickname());
        response.put("email", user.getEmail());
        response.put("role", user.getRole());
        response.put("authProvider", user.getAuthProvider());
        response.put("isNewUser", isNewUser);
        return response;
    }

    private String generateUniqueNickname(GoogleAccount googleAccount) {
        String base = nicknameBase(googleAccount.name());
        if (base.isBlank()) {
            base = nicknameBase(googleAccount.email().split("@")[0]);
        }
        if (base.length() < 3) {
            base = "reader";
        }

        String candidate = base;
        int suffix = 1;
        while (userRepository.findByNickname(candidate).isPresent()) {
            candidate = base + suffix;
            suffix++;
        }
        return candidate;
    }

    private String nicknameBase(String value) {
        if (value == null) {
            return "";
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9_]+", "_")
                .replaceAll("_+", "_")
                .replaceAll("^_|_$", "");
        return normalized.length() > 24 ? normalized.substring(0, 24) : normalized;
    }
}
