import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ebookreader/constants/api_constants.dart';

/// Сервис для работы с книгами.
///
/// Предоставляет методы для получения, поиска, добавления, обновления
/// и удаления книг через серверное API. Методы с префиксом `admin`
/// требуют прав администратора.
class BookService {
  /// Базовый URL серверного API.
  final String baseUrl = ApiConstants.baseUrl;

  /// Возвращает список всех книг, доступных пользователю.
  ///
  /// Отправляет GET-запрос на `/books`.
  /// Выбрасывает [Exception] при ошибке авторизации или сервера.
  Future<List<dynamic>> getAllBooks(String token) async {
    try {
      print('=== GET ALL BOOKS REQUEST ===');
      print('URL: $baseUrl/books');

      final response = await http.get(
        Uri.parse('$baseUrl/books'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body == '[]') {
          return [];
        }
        final data = json.decode(response.body);
        if (data is List) {
          return data;
        } else if (data is Map && data.containsKey('books')) {
          return data['books'];
        }
        return [];
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка загрузки книг: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getAllBooks: $e');
      rethrow;
    }
  }

  /// Возвращает список всех книг для панели администратора.
  ///
  /// Отправляет GET-запрос на `/admin/books`. Требует прав администратора.
  /// Выбрасывает [Exception] при отсутствии прав или ошибке сервера.
  Future<List<dynamic>> getAdminBooks(String token) async {
    try {
      print('=== GET ADMIN BOOKS REQUEST ===');
      print('URL: $baseUrl/admin/books');

      final response = await http.get(
        Uri.parse('$baseUrl/admin/books'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body == '[]') {
          return [];
        }
        final data = json.decode(response.body);
        if (data is List) {
          return data;
        } else if (data is Map && data.containsKey('books')) {
          return data['books'];
        }
        return [];
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен. Требуются права администратора');
      } else {
        throw Exception('Ошибка загрузки книг: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getAdminBooks: $e');
      rethrow;
    }
  }

  /// Возвращает данные конкретной книги по её идентификатору.
  ///
  /// Отправляет GET-запрос на `/books/{bookId}`.
  /// Выбрасывает [Exception], если книга не найдена или произошла ошибка.
  Future<Map<String, dynamic>> getBookById(String token, int bookId) async {
    try {
      print('=== GET BOOK BY ID REQUEST ===');
      print('URL: $baseUrl/books/$bookId');

      final response = await http.get(
        Uri.parse('$baseUrl/books/$bookId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Книга не найдена');
        }
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Книга не найдена');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else {
        throw Exception('Ошибка загрузки книги: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getBookById: $e');
      rethrow;
    }
  }

  /// Добавляет новую книгу (только для администратора).
  ///
  /// Отправляет POST-запрос на `/admin/books` с данными книги.
  /// Возвращает ответ сервера. Выбрасывает [Exception] при ошибке.
  Future<Map<String, dynamic>> addBook(String token, Map<String, dynamic> bookData) async {
    try {
      print('=== ADD BOOK REQUEST ===');
      print('URL: $baseUrl/admin/books');
      print('Book data: $bookData');

      final response = await http.post(
        Uri.parse('$baseUrl/admin/books'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(bookData),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.isEmpty) {
          return {'success': true, 'message': 'Книга добавлена'};
        }
        return json.decode(response.body);
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Неверные данные книги');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен. Требуются права администратора');
      } else {
        throw Exception('Ошибка добавления книги: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in addBook: $e');
      rethrow;
    }
  }

  /// Обновляет данные существующей книги (только для администратора).
  ///
  /// Отправляет PUT-запрос на `/admin/books/{bookId}`.
  /// Выбрасывает [Exception], если книга не найдена или данные некорректны.
  Future<Map<String, dynamic>> updateBook(String token, int bookId, Map<String, dynamic> bookData) async {
    try {
      print('=== UPDATE BOOK REQUEST ===');
      print('URL: $baseUrl/admin/books/$bookId');
      print('Book data: $bookData');

      final response = await http.put(
        Uri.parse('$baseUrl/admin/books/$bookId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(bookData),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return {'success': true, 'message': 'Книга обновлена'};
        }
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Книга не найдена');
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Неверные данные книги');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка обновления книги: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in updateBook: $e');
      rethrow;
    }
  }

  /// Удаляет книгу по идентификатору (только для администратора).
  ///
  /// Отправляет DELETE-запрос на `/admin/books/{bookId}`.
  /// Выбрасывает [Exception], если книга не найдена или нет прав доступа.
  Future<void> deleteBook(String token, int bookId) async {
    try {
      print('=== DELETE BOOK REQUEST ===');
      print('URL: $baseUrl/admin/books/$bookId');
      print('Token: ${token.substring(0, 20)}...'); // Показываем начало токена

      final response = await http.delete(
        Uri.parse('$baseUrl/admin/books/$bookId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        return;
      } else if (response.statusCode == 404) {
        throw Exception('Книга не найдена');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен. Требуются права администратора');
      } else {
        throw Exception('Ошибка удаления книги: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in deleteBook: $e');
      rethrow;
    }
  }

  /// Псевдоним для [getAllBooks] — для совместимости с другими частями приложения.
  Future<List<dynamic>> fetchBooks(String token) async {
    return getAllBooks(token);
  }

  /// Выполняет поиск книг по строке запроса.
  ///
  /// Отправляет GET-запрос на `/books/search?query=...`.
  /// При ошибке возвращает пустой список вместо выброса исключения.
  Future<List<dynamic>> searchBooks(String token, String query) async {
    try {
      print('=== SEARCH BOOKS REQUEST ===');
      print('Query: "$query"');
      print('URL: $baseUrl/books/search?query=$query');

      final response = await http.get(
        Uri.parse('$baseUrl/books/search?query=${Uri.encodeComponent(query)}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body == '[]') {
          return [];
        }
        final data = json.decode(response.body);
        if (data is List) {
          print('✅ Found ${data.length} books');
          return data;
        }
        return [];
      } else {
        print('⚠️ Search failed with status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error in searchBooks: $e');
      return [];
    }
  }

  /// Возвращает список глав указанной книги.
  ///
  /// Отправляет GET-запрос на `/books/{bookId}/chapters`.
  /// При ошибке или пустом ответе возвращает пустой список.
  Future<List<dynamic>> getBookChapters(String token, int bookId) async {
    try {
      print('=== GET BOOK CHAPTERS REQUEST ===');
      print('URL: $baseUrl/books/$bookId/chapters');

      final response = await http.get(
        Uri.parse('$baseUrl/books/$bookId/chapters'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body == '[]') {
          return [];
        }
        final data = json.decode(response.body);
        if (data is List) {
          return data;
        }
        return [];
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Ошибка загрузки глав: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getBookChapters: $e');
      return [];
    }
  }

  /// Возвращает содержимое конкретной главы книги.
  ///
  /// Отправляет GET-запрос на `/books/{bookId}/chapters/{chapterOrder}`.
  /// Выбрасывает [Exception], если глава не найдена или произошла ошибка.
  Future<Map<String, dynamic>> getChapter(String token, int bookId, int chapterOrder) async {
    try {
      print('=== GET CHAPTER REQUEST ===');
      print('URL: $baseUrl/books/$bookId/chapters/$chapterOrder');

      final response = await http.get(
        Uri.parse('$baseUrl/books/$bookId/chapters/$chapterOrder'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Глава не найдена');
        }
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Глава не найдена');
      } else {
        throw Exception('Ошибка загрузки главы: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getChapter: $e');
      rethrow;
    }
  }
}
