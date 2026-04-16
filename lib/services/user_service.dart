import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ebookreader/constants/api_constants.dart';

/// Сервис для работы с профилем пользователя и пользовательскими данными.
///
/// Предоставляет методы для получения и обновления профиля,
/// смены пароля, управления закладками и прогрессом чтения.
/// Методы раздела «ADMIN» требуют прав администратора.
class UserService {
  /// Базовый URL серверного API.
  final String baseUrl = ApiConstants.baseUrl;

  // ========================================
  // ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ
  // ========================================

  /// Возвращает профиль текущего авторизованного пользователя.
  ///
  /// Отправляет GET-запрос на `/user/profile`.
  /// Автоматически исправляет токен, если он содержит лишний префикс `Bearer `.
  /// Выбрасывает [Exception] при ошибке авторизации или сервера.
  Future<Map<String, dynamic>> getProfile(String token) async {
    try {
      print('=== GET PROFILE REQUEST ===');
      print('URL: $baseUrl/user/profile');
      print('Token length: ${token.length}');
      print('Token (first 50 chars): ${token.length > 50 ? token.substring(0, 50) : token}...');
      
      // Исправляем токен, если он уже содержит префикс "Bearer "
      if (token.startsWith('Bearer ')) {
        print('⚠️ WARNING: Token already contains "Bearer " prefix!');
        token = token.substring(7);
        print('Fixed token (first 50 chars): ${token.length > 50 ? token.substring(0, 50) : token}...');
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Сервер вернул пустой ответ');
        }
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка загрузки профиля: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getProfile: $e');
      rethrow;
    }
  }

  /// Обновляет никнейм текущего пользователя.
  ///
  /// Отправляет PUT-запрос на `/user/nickname`.
  /// Возвращает ответ сервера, который может содержать обновлённый JWT-токен.
  /// Выбрасывает [Exception] при ошибке.
  Future<Map<String, dynamic>> updateNickname(String token, String nickname) async {
    final response = await http.put(
      Uri.parse('$baseUrl/user/nickname'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'nickname': nickname}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception(json.decode(response.body)['message'] ?? 'Ошибка обновления никнейма');
    }
  }

  /// Псевдоним для [updateNickname] — для совместимости со старым кодом.
  Future<Map<String, dynamic>> updateProfile(String token, String newNickname) async {
    return updateNickname(token, newNickname);
  }

  /// Обновляет JWT-токен пользователя.
  ///
  /// Отправляет POST-запрос на `/auth/refresh`.
  /// Используется после операций, которые могут изменить данные токена
  /// (например, смена никнейма).
  /// Выбрасывает [Exception] при истечении сессии или ошибке сервера.
  Future<Map<String, dynamic>> refreshToken(String token) async {
    try {
      print('=== REFRESH TOKEN REQUEST ===');
      print('URL: $baseUrl/auth/refresh');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          throw Exception('Сервер вернул пустой ответ');
        }
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else {
        throw Exception('Ошибка обновления токена: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in refreshToken: $e');
      rethrow;
    }
  }

  /// Изменяет пароль текущего пользователя.
  ///
  /// Отправляет PUT-запрос на `/user/password` со старым и новым паролями.
  /// Выбрасывает [Exception], если старый пароль неверен или произошла ошибка.
  Future<void> changePassword(String token, String oldPassword, String newPassword) async {
    try {
      print('=== CHANGE PASSWORD REQUEST ===');
      print('URL: $baseUrl/user/password');

      final response = await http.put(
        Uri.parse('$baseUrl/user/password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        }),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 400) {
        if (response.body.isEmpty) {
          throw Exception('Неверный старый пароль');
        }
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Ошибка изменения пароля');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in changePassword: $e');
      rethrow;
    }
  }

  // ========================================
  // ЗАКЛАДКИ
  // ========================================

  /// Добавляет книгу в закладки пользователя.
  ///
  /// Отправляет POST-запрос на `/user/books/{bookId}/bookmark`.
  /// Выбрасывает [Exception], если книга не найдена или нет доступа.
  Future<void> addBookmark(String token, int bookId) async {
    try {
      print('=== ADD BOOKMARK REQUEST ===');
      print('URL: $baseUrl/user/books/$bookId/bookmark');

      final response = await http.post(
        Uri.parse('$baseUrl/user/books/$bookId/bookmark'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 404) {
        throw Exception('Книга не найдена');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка добавления в закладки: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in addBookmark: $e');
      rethrow;
    }
  }

  /// Удаляет книгу из закладок пользователя.
  ///
  /// Отправляет DELETE-запрос на `/user/books/{bookId}/bookmark`.
  /// Выбрасывает [Exception], если закладка не найдена или произошла ошибка.
  Future<void> removeBookmark(String token, int bookId) async {
    try {
      print('=== REMOVE BOOKMARK REQUEST ===');
      print('URL: $baseUrl/user/books/$bookId/bookmark');

      final response = await http.delete(
        Uri.parse('$baseUrl/user/books/$bookId/bookmark'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 404) {
        throw Exception('Закладка не найдена');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else {
        throw Exception('Ошибка удаления из закладок: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in removeBookmark: $e');
      rethrow;
    }
  }

  /// Возвращает список всех закладок пользователя.
  ///
  /// Отправляет GET-запрос на `/user/books/bookmarks`.
  /// При ошибке или пустом ответе возвращает пустой список.
  Future<List<dynamic>> getBookmarks(String token) async {
    try {
      print('=== GET BOOKMARKS REQUEST ===');
      print('URL: $baseUrl/user/books/bookmarks');

      final response = await http.get(
        Uri.parse('$baseUrl/user/books/bookmarks'),
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
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Ошибка загрузки закладок: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getBookmarks: $e');
      return [];
    }
  }

  /// Сохраняет прогресс чтения пользователя для указанной книги.
  ///
  /// Отправляет PUT-запрос на `/user/books/{bookId}/progress` с номером главы.
  /// Выбрасывает [Exception] при ошибке сервера.
  Future<void> updateProgress(String token, int bookId, int chapter) async {
    try {
      print('=== UPDATE PROGRESS REQUEST ===');
      print('URL: $baseUrl/user/books/$bookId/progress');

      final response = await http.put(
        Uri.parse('$baseUrl/user/books/$bookId/progress'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'chapter': chapter,
        }),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Ошибка сохранения прогресса: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in updateProgress: $e');
      rethrow;
    }
  }

  /// Возвращает сохранённый прогресс чтения для указанной книги.
  ///
  /// Отправляет GET-запрос на `/user/books/{bookId}/progress`.
  /// При ошибке возвращает значения по умолчанию:
  /// первая глава и отсутствие закладки.
  Future<Map<String, dynamic>> getProgress(String token, int bookId) async {
    try {
      print('=== GET PROGRESS REQUEST ===');
      print('URL: $baseUrl/user/books/$bookId/progress');

      final response = await http.get(
        Uri.parse('$baseUrl/user/books/$bookId/progress'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return {'currentChapter': 1, 'isBookmarked': false};
        }
        return json.decode(response.body);
      } else {
        return {'currentChapter': 1, 'isBookmarked': false};
      }
    } catch (e) {
      print('Error in getProgress: $e');
      return {'currentChapter': 1, 'isBookmarked': false};
    }
  }

  // ========================================
  // ADMIN ФУНКЦИИ
  // ========================================

  /// Возвращает список всех зарегистрированных пользователей (только для администратора).
  ///
  /// Отправляет GET-запрос на `/admin/users`. Требует прав администратора.
  /// Выбрасывает [Exception] при отсутствии прав или ошибке сервера.
  Future<List<dynamic>> getAllUsers(String token) async {
    try {
      print('=== GET ALL USERS REQUEST ===');
      print('URL: $baseUrl/admin/users');

      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return [];
        }
        final data = json.decode(response.body);
        if (data is List) {
          return data;
        } else if (data is Map && data.containsKey('users')) {
          return data['users'];
        }
        return [];
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен. Требуются права администратора');
      } else {
        throw Exception('Ошибка загрузки пользователей: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in getAllUsers: $e');
      rethrow;
    }
  }

  /// Псевдоним для [getAllUsers] — для совместимости со старым кодом.
  Future<List<dynamic>> fetchUsers(String token) async {
    return getAllUsers(token);
  }

  /// Удаляет пользователя по идентификатору (только для администратора).
  ///
  /// Отправляет DELETE-запрос на `/admin/users/{userId}`.
  /// Выбрасывает [Exception], если пользователь не найден или нет прав доступа.
  Future<void> deleteUser(String token, int userId) async {
    try {
      print('=== DELETE USER REQUEST ===');
      print('URL: $baseUrl/admin/users/$userId');

      final response = await http.delete(
        Uri.parse('$baseUrl/admin/users/$userId'),
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
        throw Exception('Пользователь не найден');
      } else if (response.statusCode == 401) {
        throw Exception('Сессия истекла. Войдите заново');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен');
      } else {
        throw Exception('Ошибка удаления пользователя: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in deleteUser: $e');
      rethrow;
    }
  }
}
