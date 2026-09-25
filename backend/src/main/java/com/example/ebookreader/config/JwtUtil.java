package com.example.ebookreader.config;

import java.security.Key;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.stereotype.Component;
import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;

@Component
public class JwtUtil {
    private final Key key;
    public JwtUtil(@Value("${ebookreader.jwt.secret:}") String secret) {
        // Local development gets an ephemeral key; deployments supply a persistent secret.
        key = secret.isBlank() ? Keys.secretKeyFor(SignatureAlgorithm.HS256)
                : Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }
    public String generateToken(Long userId, UserDetails details) {
        return generateToken(userId, details, new Date(System.currentTimeMillis() + 10 * 60 * 60 * 1000L));
    }
    public String generateToken(Long userId, UserDetails details, Date expiresAt) {
        return Jwts.builder().setClaims(Map.of("userId", userId, "authorities",
                details.getAuthorities().stream().map(GrantedAuthority::getAuthority).collect(Collectors.joining(","))))
                .setSubject(details.getUsername()).setIssuedAt(new Date())
                .setExpiration(expiresAt)
                .signWith(key, SignatureAlgorithm.HS256).compact();
    }
    public Long extractUserId(String token) {
        Number id = extractAllClaims(token).get("userId", Number.class);
        return id == null ? null : id.longValue();
    }
    public String extractUsername(String token) { return extractClaim(token, Claims::getSubject); }
    public Date extractExpiration(String token) { return extractClaim(token, Claims::getExpiration); }
    public String extractAuthorities(String token) { return extractAllClaims(token).get("authorities", String.class); }
    public <T> T extractClaim(String token, Function<Claims, T> resolver) { return resolver.apply(extractAllClaims(token)); }
    private Claims extractAllClaims(String token) {
        return Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token).getBody();
    }
    public boolean isTokenValid(String token, Long id) {
        try { return id.equals(extractUserId(token)); } catch (JwtException | IllegalArgumentException e) { return false; }
    }
    public boolean isTokenValid(String token, UserDetails details) {
        try { return details.getUsername().equals(extractUsername(token)); }
        catch (JwtException | IllegalArgumentException e) { return false; }
    }
}
