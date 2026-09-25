package com.example.ebookreader.demo;

import java.io.IOException;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import jakarta.servlet.*;
import jakarta.servlet.http.*;

/** Restricts the public demo deployment to visitor features, including paths outside Spring Security. */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
@ConditionalOnProperty(name = "ebookreader.demo.enabled", havingValue = "true")
public class DemoBoundaryFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String p = req.getRequestURI();
        boolean read = req.getMethod().equals("GET") || req.getMethod().equals("HEAD");
        boolean allowed = p.startsWith("/api/demo/") || p.startsWith("/api/user/books/")
                || p.equals("/api/lookup/selection") || p.equals("/api/user/profile") || p.startsWith("/api/recommendations/")
                || (read && (p.equals("/api/books") || p.startsWith("/api/books/")
                    || p.startsWith("/api/genres") || p.startsWith("/covers/") || p.startsWith("/assets/")))
                || p.equals("/error");
        if (!allowed) { res.sendError(404); return; }
        res.setHeader("Cache-Control", "no-store");
        res.setHeader("X-Content-Type-Options", "nosniff");
        chain.doFilter(req, res);
    }
}
