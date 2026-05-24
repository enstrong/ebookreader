package com.example.ebookreader.service.google;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.Collections;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.example.ebookreader.exception.BadRequestException;
import com.example.ebookreader.exception.UnauthorizedException;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.javanet.NetHttpTransport;
import com.google.api.client.json.JsonFactory;
import com.google.api.client.json.gson.GsonFactory;

@Service
public class GoogleTokenVerifierImpl implements GoogleTokenVerifier {

    private final String webClientId;
    private final NetHttpTransport transport = new NetHttpTransport();
    private final JsonFactory jsonFactory = GsonFactory.getDefaultInstance();

    public GoogleTokenVerifierImpl(
            @Value("${google.auth.web-client-id:${GOOGLE_WEB_CLIENT_ID:}}") String webClientId) {
        this.webClientId = webClientId == null ? "" : webClientId.trim();
    }

    @Override
    public GoogleAccount verify(String idTokenString) {
        if (webClientId.isEmpty()) {
            throw new BadRequestException("Google authentication is not configured on the server");
        }

        try {
            GoogleIdTokenVerifier verifier = new GoogleIdTokenVerifier.Builder(transport, jsonFactory)
                    .setAudience(Collections.singletonList(webClientId))
                    .build();

            GoogleIdToken idToken = verifier.verify(idTokenString);
            if (idToken == null) {
                throw new UnauthorizedException("Недействительный Google ID token");
            }

            GoogleIdToken.Payload payload = idToken.getPayload();
            String subject = payload.getSubject();
            String email = payload.getEmail();
            boolean emailVerified = Boolean.TRUE.equals(payload.getEmailVerified());
            String name = (String) payload.get("name");

            if (subject == null || subject.isBlank()) {
                throw new UnauthorizedException("Google account identifier is missing");
            }
            if (email == null || email.isBlank()) {
                throw new UnauthorizedException("Google account email is missing");
            }
            if (!emailVerified) {
                throw new UnauthorizedException("Google email is not verified");
            }

            return new GoogleAccount(subject, email.trim().toLowerCase(), true, name);
        } catch (GeneralSecurityException | IOException e) {
            throw new UnauthorizedException("Не удалось проверить Google ID token");
        }
    }
}
