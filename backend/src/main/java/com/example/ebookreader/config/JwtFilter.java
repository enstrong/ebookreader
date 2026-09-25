package com.example.ebookreader.config;

import java.io.IOException;
import java.time.Instant;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import com.example.ebookreader.service.CustomUserDetailsService;
import com.example.ebookreader.repository.UserRepository;
import com.example.ebookreader.demo.DemoAccess;
import jakarta.servlet.*;
import jakarta.servlet.http.*;

@Component
public class JwtFilter extends OncePerRequestFilter {
    private final JwtUtil jwt;
    private final CustomUserDetailsService details;
    private final UserRepository users;
    public JwtFilter(JwtUtil jwt, CustomUserDetailsService details, UserRepository users) {
        this.jwt = jwt; this.details = details; this.users = users;
    }
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            String header = request.getHeader("Authorization");
            if (header != null && header.startsWith("Bearer ")) {
                try {
                    Long id = jwt.extractUserId(header.substring(7));
                    var user = users.findById(id).orElseThrow();
                    if (user.getDemoExpiresAt() != null && !user.getDemoExpiresAt().isAfter(Instant.now())) {
                        unauthorized(response, "Demo session expired"); return;
                    }
                    var principal = details.loadUserById(id);
                    var auth = new UsernamePasswordAuthenticationToken(principal, null, principal.getAuthorities());
                    auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                    SecurityContextHolder.getContext().setAuthentication(auth);
                    DemoAccess.enter(id, user.getDemoExpiresAt() != null);
                } catch (RuntimeException e) {
                    unauthorized(response, "Invalid session"); return;
                }
            }
            chain.doFilter(request, response);
        } finally { DemoAccess.clear(); }
    }
    private void unauthorized(HttpServletResponse response,String message) throws IOException {
        response.setStatus(401);
        response.setContentType("application/json");
        response.getWriter().write("{\"message\":\""+message+"\"}");
    }
}
