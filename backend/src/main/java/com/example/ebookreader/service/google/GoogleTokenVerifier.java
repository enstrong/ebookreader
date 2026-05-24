package com.example.ebookreader.service.google;

public interface GoogleTokenVerifier {
    GoogleAccount verify(String idToken);
}
