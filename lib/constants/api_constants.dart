import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Константы для работы с серверным API.
///
/// Все URL формируются на основе базового адреса сервера,
/// заданного в переменной окружения `API_BASE_URL` файла `.env`.
class ApiConstants {
  /// Базовый URL API (включает префикс `/api`).
  static String get baseUrl => '${dotenv.env['API_BASE_URL']}/api';

  /// URL для эндпоинтов аутентификации (`/api/auth`).
  static String get authUrl => '$baseUrl/auth';

  /// URL для эндпоинтов панели администратора (`/api/admin`).
  static String get adminUrl => '$baseUrl/admin';

  /// URL для эндпоинтов работы с книгами (`/api/books`).
  static String get booksUrl => '$baseUrl/books';

  /// OAuth client ID used by the backend to verify Google ID tokens.
  static String get googleWebClientId =>
      dotenv.env['GOOGLE_WEB_CLIENT_ID']?.trim() ?? '';

  /// iOS OAuth client ID for native Google Sign-In.
  static String get googleIosClientId =>
      dotenv.env['GOOGLE_IOS_CLIENT_ID']?.trim() ?? '';

  /// Формирует полный URL для обложки книги по относительному пути.
  ///
  /// Если [coverPath] начинается с `/`, URL формируется как `{host}{coverPath}`.
  /// В противном случае добавляется разделитель `/`.
  static String getCoverUrl(String coverPath) {
    final apiBase = dotenv.env['API_BASE_URL'] ?? 'http://192.168.1.90:8080';

    // Если это уже полный URL
    if (coverPath.startsWith('http')) {
      return _preferLargeGoodreadsCover(coverPath);
    }

    // Получаем имя файла
    String filename = coverPath;
    if (coverPath.contains('/')) {
      filename = coverPath.split('/').last;
    }

    // Возвращаем прямой путь к статике
    return '$apiBase/covers/$filename';
  }

  static String _preferLargeGoodreadsCover(String url) {
    if (!url.contains('gr-assets.com/books/')) return url;
    return url.replaceFirstMapped(
      RegExp(r'/books/(\d+)[ms]/'),
      (match) => '/books/${match.group(1)}l/',
    );
  }

  /// Формирует полный URL для потокового аудио.
  static String getAudioUrl(String streamPath) {
    final apiBase = dotenv.env['API_BASE_URL'] ?? 'http://192.168.1.90:8080';
    if (streamPath.startsWith('http')) return streamPath;
    if (streamPath.startsWith('/')) return '$apiBase$streamPath';
    return '$baseUrl/$streamPath';
  }
}
