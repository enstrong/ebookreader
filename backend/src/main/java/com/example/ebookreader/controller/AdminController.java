package com.example.ebookreader.controller;

import java.io.IOException;
import java.nio.file.Files;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.example.ebookreader.dto.ChapterDTO;
import com.example.ebookreader.model.Book;
import com.example.ebookreader.model.Chapter;
import com.example.ebookreader.model.User;
import com.example.ebookreader.service.AdminService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;

@RestController
@RequestMapping("/api/admin")
@CrossOrigin(origins = "*")
@PreAuthorize("hasRole(\'ADMIN\')")
@Tag(name = "Администрирование", description = "API для управления книгами, главами и пользователями")
public class AdminController {

    private final AdminService adminService;

    @Autowired
    public AdminController(AdminService adminService) {
        this.adminService = adminService;
    }

    // === УПРАВЛЕНИЕ КНИГАМИ ===

    @Operation(summary = "Получить список всех книг")
    @ApiResponse(responseCode = "200", description = "Успешный запрос")
    @GetMapping("/books")
    public ResponseEntity<List<Book>> getAllBooks() {
        return ResponseEntity.ok(adminService.getAllBooks());
    }

    @Operation(summary = "Получить книгу по ID")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Книга найдена"),
            @ApiResponse(responseCode = "404", description = "Книга не найдена")
    })
    @GetMapping("/books/{id}")
    public ResponseEntity<Book> getBook(@PathVariable Long id) {
        return adminService.getBookById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(summary = "Создать новую книгу")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "201", description = "Книга успешно создана"),
            @ApiResponse(responseCode = "400", description = "Неверные входные данные"),
            @ApiResponse(responseCode = "500", description = "Ошибка сервера")
    })
    @PostMapping(value = "/books", consumes = "multipart/form-data")
    public ResponseEntity<Book> createBook(
            @RequestPart("title") String title,
            @RequestPart("author") String author,
            @RequestPart(value = "description", required = false) String description,
            @RequestPart(value = "genres", required = false) List<String> genres,
            @RequestPart(value = "cover", required = false) MultipartFile cover
    ) throws IOException {
        Book newBook = adminService.createBook(title, author, description, genres, cover);
        return ResponseEntity.status(HttpStatus.CREATED).body(newBook);
    }

    @Operation(summary = "Обновить существующую книгу")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Книга успешно обновлена"),
            @ApiResponse(responseCode = "404", description = "Книга не найдена"),
            @ApiResponse(responseCode = "500", description = "Ошибка сервера")
    })
    @PutMapping(value = "/books/{id}")
    public ResponseEntity<Book> updateBook(@PathVariable Long id, @RequestBody Book bookDetails) {
        Book updatedBook = adminService.updateBook(id, bookDetails);
        return ResponseEntity.ok(updatedBook);
    }

    @Operation(summary = "Удалить книгу по ID")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Книга успешно удалена"),
            @ApiResponse(responseCode = "404", description = "Книга не найдена")
    })
    @DeleteMapping("/books/{id}")
    public ResponseEntity<Void> deleteBook(@PathVariable Long id) {
        adminService.deleteBook(id);
        return ResponseEntity.ok().build();
    }

    @Operation(summary = "Получить обложку книги")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Обложка найдена"),
            @ApiResponse(responseCode = "404", description = "Обложка не найдена"),
            @ApiResponse(responseCode = "500", description = "Ошибка сервера")
    })
    @GetMapping("/covers/{filename}")
    public ResponseEntity<Resource> getCover(@PathVariable String filename) throws IOException {
        Resource resource = adminService.getCover(filename);
        String contentType = Files.probeContentType(resource.getFile().toPath());
        if (contentType == null) contentType = "application/octet-stream";
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(contentType))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + resource.getFilename() + "\"")
                .body(resource);
    }

    // === УПРАВЛЕНИЕ ГЛАВАМИ ===

    @Operation(summary = "Получить список глав книги")
    @ApiResponse(responseCode = "200", description = "Успешный запрос")
    @GetMapping("/books/{bookId}/chapters")
    public ResponseEntity<List<Chapter>> getChapters(@PathVariable Long bookId) {
        return ResponseEntity.ok(adminService.getChapters(bookId));
    }

    @Operation(summary = "Создать новую главу для книги")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Глава успешно создана"),
            @ApiResponse(responseCode = "404", description = "Книга не найдена"),
            @ApiResponse(responseCode = "500", description = "Ошибка сервера")
    })
    @PostMapping("/books/{bookId}/chapters")
    public ResponseEntity<Chapter> createChapter(@PathVariable Long bookId, @RequestBody ChapterDTO dto) {
        Chapter newChapter = adminService.createChapter(bookId, dto);
        return ResponseEntity.ok(newChapter);
    }

    @Operation(summary = "Обновить главу книги")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Глава успешно обновлена"),
            @ApiResponse(responseCode = "404", description = "Глава или книга не найдена"),
            @ApiResponse(responseCode = "500", description = "Ошибка сервера")
    })
    @PutMapping("/books/{bookId}/chapters/{chapterId}")
    public ResponseEntity<Chapter> updateChapter(
            @PathVariable Long bookId,
            @PathVariable Long chapterId,
            @RequestBody ChapterDTO dto) {
        Chapter updatedChapter = adminService.updateChapter(bookId, chapterId, dto);
        return ResponseEntity.ok(updatedChapter);
    }

    @Operation(summary = "Удалить главу книги")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Глава успешно удалена"),
            @ApiResponse(responseCode = "404", description = "Глава или книга не найдена")
    })
    @DeleteMapping("/books/{bookId}/chapters/{chapterId}")
    public ResponseEntity<Void> deleteChapter(@PathVariable Long bookId, @PathVariable Long chapterId) {
        adminService.deleteChapter(bookId, chapterId);
        return ResponseEntity.ok().build();
    }

    // === УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ ===

    @Operation(summary = "Получить список всех пользователей")
    @ApiResponse(responseCode = "200", description = "Успешный запрос")
    @GetMapping("/users")
    public ResponseEntity<List<User>> getAllUsers() {
        return ResponseEntity.ok(adminService.getAllUsers());
    }

    @Operation(summary = "Получить пользователя по ID")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Пользователь найден"),
            @ApiResponse(responseCode = "404", description = "Пользователь не найден")
    })
    @GetMapping("/users/{id}")
    public ResponseEntity<User> getUserById(@PathVariable Long id) {
        return adminService.getUserById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @Operation(summary = "Обновить роль пользователя")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Роль пользователя обновлена"),
            @ApiResponse(responseCode = "404", description = "Пользователь не найден"),
            @ApiResponse(responseCode = "500", description = "Ошибка сервера")
    })
    @PutMapping("/users/{id}/role")
    public ResponseEntity<User> updateUserRole(@PathVariable Long id, @RequestParam String newRole) {
        User updatedUser = adminService.updateUserRole(id, newRole);
        return ResponseEntity.ok(updatedUser);
    }

    @Operation(summary = "Удалить пользователя по ID")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Пользователь успешно удален"),
            @ApiResponse(responseCode = "404", description = "Пользователь не найден")
    })
    @DeleteMapping("/users/{id}")
    public ResponseEntity<Void> deleteUser(@PathVariable Long id) {
        adminService.deleteUser(id);
        return ResponseEntity.ok().build();
    }
}
