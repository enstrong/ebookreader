import 'dart:convert';

import 'package:ebookreader/constants/api_constants.dart';
import 'package:http/http.dart' as http;

class RecommendationService {
  final String baseUrl = ApiConstants.baseUrl;

  Future<Map<String, dynamic>> getForYou(String token, {int limit = 50}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/recommendations/me?limit=$limit'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _decodeMap(response, 'Ошибка загрузки рекомендаций');
  }

  Future<List<dynamic>> getSimilarBooks(
    String token,
    int bookId, {
    int limit = 4,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/recommendations/books/$bookId/similar?limit=$limit'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final data = _decodeMap(response, 'Ошибка загрузки похожих книг');
    return (data['similar'] as List? ?? []).cast<dynamic>();
  }

  Future<Map<String, dynamic>> preview(
    String token,
    List<Map<String, dynamic>> interactions, {
    int limit = 50,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/recommendations/preview?limit=$limit'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'interactions': interactions}),
    );
    return _decodeMap(response, 'Ошибка предварительных рекомендаций');
  }

  Map<String, dynamic> _decodeMap(http.Response response, String message) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{};
    }
    throw Exception('$message: ${response.statusCode}');
  }
}
