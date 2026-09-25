package com.example.ebookreader.config;

import java.util.List;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configuration.WebSecurityCustomizer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;

@Configuration
@EnableWebSecurity
public class SecurityConfig {
    
    private final JwtFilter jwtFilter;

    public SecurityConfig(JwtFilter jwtFilter) {
        this.jwtFilter = jwtFilter;
    }

    @Bean
    public org.springframework.boot.web.servlet.FilterRegistrationBean<JwtFilter> jwtRegistration(JwtFilter filter) {
        var registration = new org.springframework.boot.web.servlet.FilterRegistrationBean<>(filter);
        registration.setEnabled(false); // Run once, inside the security chain.
        return registration;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    // ✅ КРИТИЧЕСКИ ВАЖНО: Полностью отключаем проверку безопасности для GraphQL
    @Bean
    public WebSecurityCustomizer webSecurityCustomizer() {
        return (web) -> web.ignoring()
            .requestMatchers("/graphql/**", "/graphiql/**", "/favicon.ico");
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .cors(cors -> cors.configurationSource(request -> {
                CorsConfiguration config = new CorsConfiguration();
                config.setAllowedOrigins(List.of("*"));
                config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
                config.setAllowedHeaders(List.of("*"));
                config.setAllowCredentials(false);
                return config;
            }))
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                // ✅ Публичные эндпоинты
                .requestMatchers("/error").permitAll()
                .requestMatchers("/api/auth/**").permitAll()
                .requestMatchers("/api/demo/session", "/api/demo/health").permitAll()
                .requestMatchers("/api/books/**").permitAll()
                .requestMatchers("/api/genres/**").permitAll()
                .requestMatchers("/api/test/**").permitAll()
                
                // ✅ Статические файлы
                .requestMatchers("/covers/**").permitAll()
                .requestMatchers("/assets/**").permitAll()
                .requestMatchers("/api/admin/covers/**").permitAll()
                
                // ✅ Swagger UI
                .requestMatchers("/swagger-ui/**").permitAll()
                .requestMatchers("/v3/api-docs/**").permitAll()
                .requestMatchers("/swagger-ui.html").permitAll()

                // ✅ GraphQL (уже игнорируется WebSecurityCustomizer, но оставляем для надежности)
                .requestMatchers("/graphql/**").permitAll()
                .requestMatchers("/graphiql/**").permitAll()
                
                // ✅ Защищенные эндпоинты
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .requestMatchers("/api/user/**").hasAnyRole("USER", "ADMIN")
                
                .anyRequest().authenticated()
            )
            // ✅ Оставляем только один фильтр (JwtFilter)
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class);
        
        return http.build();
    }
}
