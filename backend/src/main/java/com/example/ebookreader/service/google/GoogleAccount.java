package com.example.ebookreader.service.google;

public record GoogleAccount(
        String subject,
        String email,
        boolean emailVerified,
        String name
) {
}
