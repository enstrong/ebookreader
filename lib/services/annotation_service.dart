import 'dart:convert';

import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/book_annotation.dart';
import 'package:http/http.dart' as http;

class AnnotationService {
  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<List<BookAnnotation>> getBookAnnotations(String token, int bookId) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/annotations'),
      headers: _headers(token),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки заметок: ${response.statusCode}');
    }
    if (response.body.isEmpty || response.body == '[]') return [];
    final data = json.decode(response.body);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((item) => BookAnnotation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<List<BookAnnotation>> getChapterAnnotations(
    String token,
    int bookId,
    int chapterOrder,
  ) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/chapters/$chapterOrder/annotations'),
      headers: _headers(token),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка загрузки выделений: ${response.statusCode}');
    }
    if (response.body.isEmpty || response.body == '[]') return [];
    final data = json.decode(response.body);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((item) => BookAnnotation.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<BookAnnotation> createAnnotation({
    required String token,
    required int bookId,
    required int chapterOrder,
    required int startOffset,
    required int endOffset,
    required String highlightedText,
    String note = '',
    String color = '#14FFEC',
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/annotations'),
      headers: _headers(token),
      body: json.encode({
        'chapterOrder': chapterOrder,
        'startOffset': startOffset,
        'endOffset': endOffset,
        'highlightedText': highlightedText,
        'note': note,
        'color': color,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка сохранения выделения: ${response.statusCode}');
    }
    return BookAnnotation.fromJson(json.decode(response.body));
  }

  Future<BookAnnotation> updateAnnotation({
    required String token,
    required int bookId,
    required int annotationId,
    required String note,
    String color = '#14FFEC',
  }) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/annotations/$annotationId'),
      headers: _headers(token),
      body: json.encode({
        'note': note,
        'color': color,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка обновления заметки: ${response.statusCode}');
    }
    return BookAnnotation.fromJson(json.decode(response.body));
  }

  Future<void> deleteAnnotation(String token, int bookId, int annotationId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/annotations/$annotationId'),
      headers: _headers(token),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка удаления заметки: ${response.statusCode}');
    }
  }
}
