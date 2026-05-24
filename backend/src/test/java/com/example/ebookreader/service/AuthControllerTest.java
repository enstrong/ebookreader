package com.example.ebookreader.service;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import static org.mockito.ArgumentMatchers.any;
import org.mockito.InjectMocks;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import org.mockito.MockitoAnnotations;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;

import com.example.ebookreader.config.JwtUtil;
import com.example.ebookreader.controller.AuthController;
import com.example.ebookreader.dto.GoogleAuthRequest;
import com.example.ebookreader.dto.LoginRequest;
import com.example.ebookreader.model.User;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.service.google.GoogleAccount;
import com.example.ebookreader.service.google.GoogleTokenVerifier;

class AuthControllerTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private JwtUtil jwtUtil;

    @Mock
    private GoogleTokenVerifier googleTokenVerifier;

    @InjectMocks
    private AuthController authController;

    @BeforeEach
    void setUp() {
        MockitoAnnotations.openMocks(this);
    }

    @Test
    void testLoginSuccess() {
        // Given
        LoginRequest request = new LoginRequest();
        request.setUsername("testuser");
        request.setPassword("password123");

        User user = new User();
        user.setNickname("testuser");
        user.setPassword("hashed_password");
        user.setRole("USER");

        when(userRepository.findByNickname("testuser")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("password123", "hashed_password")).thenReturn(true);
        when(jwtUtil.generateToken(any(), any())).thenReturn("mocked_token");

        // When
        ResponseEntity<?> response = authController.login(request);

        // Then
        assertEquals(200, response.getStatusCodeValue());
        verify(userRepository).findByNickname("testuser");
    }

    @Test
    void testLoginFailureInvalidPassword() {
        // Given
        LoginRequest request = new LoginRequest();
        request.setUsername("testuser");
        request.setPassword("wrong_password");

        User user = new User();
        user.setNickname("testuser");
        user.setPassword("hashed_password");

        when(userRepository.findByNickname("testuser")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong_password", "hashed_password")).thenReturn(false);

        // When
        ResponseEntity<?> response = authController.login(request);

        // Then
        assertEquals(401, response.getStatusCodeValue());
    }

    @Test
    void testGoogleAuthCreatesNewUser() {
        GoogleAuthRequest request = new GoogleAuthRequest();
        request.setIdToken("google_id_token");

        when(googleTokenVerifier.verify("google_id_token"))
                .thenReturn(new GoogleAccount("google-sub-1", "reader@example.com", true, "Reader One"));
        when(userRepository.findByGoogleSubject("google-sub-1")).thenReturn(Optional.empty());
        when(userRepository.findByEmailIgnoreCase("reader@example.com")).thenReturn(Optional.empty());
        when(userRepository.findByNickname("reader_one")).thenReturn(Optional.empty());
        when(passwordEncoder.encode(any())).thenReturn("encoded_google_password");
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User saved = invocation.getArgument(0);
            saved.setId(10L);
            return saved;
        });
        when(jwtUtil.generateToken(any(), any())).thenReturn("mocked_google_token");

        ResponseEntity<?> response = authController.googleAuth(request);

        assertEquals(200, response.getStatusCodeValue());
        ArgumentCaptor<User> userCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(userCaptor.capture());
        User savedUser = userCaptor.getValue();
        assertEquals("reader@example.com", savedUser.getEmail());
        assertEquals("google-sub-1", savedUser.getGoogleSubject());
        assertEquals("GOOGLE", savedUser.getAuthProvider());
        assertNotNull(savedUser.getPassword());
    }

    @Test
    void testGoogleAuthReturnsExistingGoogleUser() {
        GoogleAuthRequest request = new GoogleAuthRequest();
        request.setIdToken("google_id_token");

        User user = new User();
        user.setId(11L);
        user.setNickname("reader");
        user.setEmail("reader@example.com");
        user.setPassword("encoded_google_password");
        user.setRole("USER");
        user.setGoogleSubject("google-sub-1");

        when(googleTokenVerifier.verify("google_id_token"))
                .thenReturn(new GoogleAccount("google-sub-1", "reader@example.com", true, "Reader One"));
        when(userRepository.findByGoogleSubject("google-sub-1")).thenReturn(Optional.of(user));
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(jwtUtil.generateToken(any(), any())).thenReturn("mocked_google_token");

        ResponseEntity<?> response = authController.googleAuth(request);

        assertEquals(200, response.getStatusCodeValue());
        verify(userRepository).findByGoogleSubject("google-sub-1");
    }

    @Test
    void testGoogleAuthAutoLinksExistingEmail() {
        GoogleAuthRequest request = new GoogleAuthRequest();
        request.setIdToken("google_id_token");

        User user = new User();
        user.setId(12L);
        user.setNickname("local_reader");
        user.setEmail("reader@example.com");
        user.setPassword("encoded_password");
        user.setRole("USER");

        when(googleTokenVerifier.verify("google_id_token"))
                .thenReturn(new GoogleAccount("google-sub-1", "reader@example.com", true, "Reader One"));
        when(userRepository.findByGoogleSubject("google-sub-1")).thenReturn(Optional.empty());
        when(userRepository.findByEmailIgnoreCase("reader@example.com")).thenReturn(Optional.of(user));
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(jwtUtil.generateToken(any(), any())).thenReturn("mocked_google_token");

        ResponseEntity<?> response = authController.googleAuth(request);

        assertEquals(200, response.getStatusCodeValue());
        assertEquals("google-sub-1", user.getGoogleSubject());
    }
}
