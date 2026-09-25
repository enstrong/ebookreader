package com.example.ebookreader.config;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

public class JwtAuthenticationFilter extends OncePerRequestFilter {

    @Autowired
    private JwtUtil jwtUtil;

    @Autowired
    private UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        
        try {
            String path = request.getRequestURI();
            
            // ✅ ДОБАВЛЕНО: Пропускаем GraphQL, чтобы не мешать загрузке
            if (path.startsWith("/api/auth/") || 
                path.startsWith("/api/books") || 
                path.startsWith("/api/genres") ||
                path.startsWith("/api/test/") ||
                path.startsWith("/covers/") ||
                path.startsWith("/assets/") ||
                path.startsWith("/graphql") ||   // ← ДОБАВЛЕНО
                path.startsWith("/graphiql")) {  // ← ДОБАВЛЕНО
                
                filterChain.doFilter(request, response);
                return;
            }
            
            final String authHeader = request.getHeader("Authorization");
            final String jwt;
            final String username;

            if (authHeader == null || !authHeader.startsWith("Bearer ")) {
                filterChain.doFilter(request, response);
                return;
            }

            jwt = authHeader.substring(7);
            username = jwtUtil.extractUsername(jwt);

            if (username != null && SecurityContextHolder.getContext().getAuthentication() == null) {
                UserDetails userDetails = userDetailsService.loadUserByUsername(username);

                if (jwtUtil.isTokenValid(jwt, userDetails)) {
                    String authoritiesString = jwtUtil.extractAuthorities(jwt);
                    List<SimpleGrantedAuthority> authorities;
                    
                    if (authoritiesString != null && !authoritiesString.isEmpty()) {
                        authorities = Arrays.stream(authoritiesString.split(","))
                                .map(SimpleGrantedAuthority::new)
                                .collect(Collectors.toList());
                    } else {
                        authorities = userDetails.getAuthorities().stream()
                                .map(auth -> new SimpleGrantedAuthority(auth.getAuthority()))
                                .collect(Collectors.toList());
                    }

                    UsernamePasswordAuthenticationToken authToken = new UsernamePasswordAuthenticationToken(
                            userDetails,
                            null,
                            authorities
                    );

                    authToken.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                    SecurityContextHolder.getContext().setAuthentication(authToken);
                }
            }

            filterChain.doFilter(request, response);
            
        } catch (Exception e) {
            filterChain.doFilter(request, response);
        }
    }
}
