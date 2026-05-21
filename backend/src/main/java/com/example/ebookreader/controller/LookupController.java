package com.example.ebookreader.controller;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.ebookreader.dto.LookupRequest;
import com.example.ebookreader.service.LookupService;

@RestController
@RequestMapping("/api/lookup")
@CrossOrigin(origins = "*")
public class LookupController {

    private final LookupService lookupService;

    public LookupController(LookupService lookupService) {
        this.lookupService = lookupService;
    }

    @PostMapping("/selection")
    public ResponseEntity<?> lookupSelection(
            @RequestHeader("Authorization") String token,
            @RequestBody LookupRequest request) {
        String text = request.getText() == null ? "" : request.getText().trim();
        if (text.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("message", "Текст обязателен"));
        }
        if (text.length() > 500) {
            return ResponseEntity.badRequest().body(Map.of("message", "Выделение слишком длинное"));
        }

        return ResponseEntity.ok(lookupService.lookup(request));
    }
}
