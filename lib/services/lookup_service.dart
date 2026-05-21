import 'dart:convert';

import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/lookup_result.dart';
import 'package:http/http.dart' as http;

class LookupService {
  Future<LookupResult> lookupSelection({
    required String token,
    required String text,
    String sourceLanguage = 'auto',
    String? targetLanguage,
  }) async {
    final payload = <String, dynamic>{
      'text': text,
      'sourceLanguage': sourceLanguage,
    };
    if (targetLanguage != null) {
      payload['targetLanguage'] = targetLanguage;
    }

    var response = await _postLookup(
      '${ApiConstants.baseUrl}/lookup/selection',
      token,
      payload,
    );
    if (_looksLikeMissingLookupEndpoint(response)) {
      response = await _postLookup(
        '${ApiConstants.baseUrl}/user/books/lookup/selection',
        token,
        payload,
      );
    }

    if (response.statusCode == 200) {
      return LookupResult.fromJson(json.decode(response.body));
    }

    throw Exception(_errorMessage(response));
  }

  Future<http.Response> _postLookup(
    String url,
    String token,
    Map<String, dynamic> payload,
  ) {
    return http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(payload),
    );
  }

  bool _looksLikeMissingLookupEndpoint(http.Response response) {
    if (response.statusCode != 404 && response.statusCode != 500) {
      return false;
    }
    return response.body.contains('No static resource') ||
        response.body.contains('/api/lookup/selection') ||
        response.body.contains('api/lookup/selection');
  }

  String _errorMessage(http.Response response) {
    var message = 'Ошибка словаря: ${response.statusCode}';
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        message = decoded['message'].toString();
      }
    } catch (_) {
      if (response.body.isNotEmpty) {
        message = response.body;
      }
    }
    return message;
  }
}
