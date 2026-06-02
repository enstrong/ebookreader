import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ebookreader/constants/api_constants.dart';

/// Сервис для управления закладками и прогрессом чтения.
///
/// Предоставляет методы для добавления и удаления книг из закладок,
/// получения списка сохранённых книг, а также сохранения и получения
/// прогресса чтения пользователя.
class BookmarkService {
  /// Добавляет книгу в закладки текущего пользователя.
  ///
  /// Отправляет POST-запрос на `/user/books/{bookId}/bookmark`.
  /// Выбрасывает [Exception] при ошибке сервера.
  Future<void> addBookmark(String token, int bookId) async {
    try {
      print('=== ADD BOOKMARK ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/bookmark');

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/bookmark'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Ошибка добавления в закладки: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in addBookmark: $e');
      rethrow;
    }
  }

  /// Удаляет книгу из закладок текущего пользователя.
  ///
  /// Отправляет DELETE-запрос на `/user/books/{bookId}/bookmark`.
  /// Выбрасывает [Exception] при ошибке сервера.
  Future<void> removeBookmark(String token, int bookId) async {
    try {
      print('=== REMOVE BOOKMARK ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/bookmark');

      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/bookmark'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Ошибка удаления из закладок: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in removeBookmark: $e');
      rethrow;
    }
  }

  /// Удаляет книгу из библиотеки, не стирая оценку или отзыв пользователя.
  Future<void> removeFromLibrary(String token, int bookId) async {
    try {
      print('=== REMOVE FROM LIBRARY ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/library');

      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/library'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Ошибка удаления из библиотеки: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error in removeFromLibrary: $e');
      rethrow;
    }
  }

  /// Возвращает список книг, добавленных пользователем в закладки.
  ///
  /// Отправляет GET-запрос на `/user/books/bookmarks`.
  /// При пустом ответе возвращает пустой список.
  Future<List<dynamic>> getBookmarks(String token, {int limit = 50}) async {
    try {
      print('=== GET BOOKMARKS ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/bookmarks?limit=$limit');

      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/user/books/bookmarks?limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty || response.body == '[]') {
          return [];
        }
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception(
          'Ошибка загрузки сохранённых книг: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      print('Error in getBookmarks: $e');
      rethrow;
    }
  }

  /// Сохраняет личную оценку пользователя для книги.
  ///
  /// Рейтинг 1-5 является явной оценкой; 0 удаляет оценку.
  Future<int> updateRating(String token, int bookId, int rating) async {
    if (rating < 0 || rating > 5) {
      throw Exception('Оценка должна быть от 0 до 5');
    }

    try {
      if (rating == 0) {
        print('=== CLEAR RATING ===');
        print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/rating');

        final response = await http.delete(
          Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/rating'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        print('Status: ${response.statusCode}');
        print('Body: ${response.body}');

        if (response.statusCode == 200) {
          return 0;
        }
      }

      print('=== UPDATE RATING ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/rating');
      print('Rating: $rating');

      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/rating'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'rating': rating}),
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final savedRating = data['rating'];
        if (savedRating is int) return savedRating;
        if (savedRating is num) return savedRating.toInt();
        return int.tryParse(savedRating?.toString() ?? '') ?? rating;
      }

      throw Exception(
        'Ошибка сохранения оценки: ${response.statusCode} ${response.body}',
      );
    } catch (e) {
      print('Error in updateRating: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> markAsRead(String token, int bookId) async {
    try {
      print('=== MARK AS READ ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/finish');

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/finish'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) return {};
        return json.decode(response.body) as Map<String, dynamic>;
      }

      throw Exception(
        'Ошибка отметки книги: ${response.statusCode} ${response.body}',
      );
    } catch (e) {
      print('Error in markAsRead: $e');
      rethrow;
    }
  }

  /// Сохраняет прогресс чтения пользователя для указанной книги.
  ///
  /// Отправляет PUT-запрос на `/user/books/{bookId}/progress`
  /// с номером текущей главы. Выбрасывает [Exception] при ошибке.
  Future<void> updateProgress(
    String token,
    int bookId,
    int chapter, {
    double? segmentProgress,
    int? audioPositionMs,
    String? lastMode,
  }) async {
    try {
      print('=== UPDATE PROGRESS ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/progress');
      print('Chapter: $chapter');
      final payload = <String, dynamic>{
        'chapter': chapter,
        'segmentOrder': chapter,
      };
      if (segmentProgress != null) {
        payload['segmentProgress'] = segmentProgress.clamp(0.0, 1.0);
      }
      if (audioPositionMs != null) {
        payload['audioPositionMs'] = audioPositionMs < 0 ? 0 : audioPositionMs;
      }
      if (lastMode != null) {
        payload['lastMode'] = lastMode;
      }

      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/progress'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(payload),
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Ошибка сохранения прогресса: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in updateProgress: $e');
      rethrow;
    }
  }

  /// Возвращает сохранённый прогресс чтения пользователя для указанной книги.
  ///
  /// Отправляет GET-запрос на `/user/books/{bookId}/progress`.
  /// При ошибке возвращает значения по умолчанию:
  /// первая глава и отсутствие закладки.
  Future<Map<String, dynamic>> getProgress(String token, int bookId) async {
    try {
      print('=== GET PROGRESS ===');
      print('URL: ${ApiConstants.baseUrl}/user/books/$bookId/progress');

      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/progress'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return {'currentChapter': 1, 'isBookmarked': false, 'rating': 0};
        }
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        decoded['rating'] ??= 0;
        return decoded;
      } else {
        return {'currentChapter': 1, 'isBookmarked': false, 'rating': 0};
      }
    } catch (e) {
      print('Error in getProgress: $e');
      return {'currentChapter': 1, 'isBookmarked': false, 'rating': 0};
    }
  }
}
