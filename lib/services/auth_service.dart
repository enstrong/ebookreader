import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  final String baseUrl = 'http://192.168.1.90:8080/api';

  Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    try {
      print('=== REGISTRATION REQUEST ===');
      print('URL: $baseUrl/auth/register');
      print('Username: $username');
      print('Email: $email');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Ошибка регистрации');
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in register: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      print('=== LOGIN REQUEST ===');
      print('URL: $baseUrl/auth/login');
      print('Username/Email: $username');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Login successful!');
        print('Token received: ${data['token']?.substring(0, 20)}...');
        print('Role: ${data['role']}');
        return data;
      } else if (response.statusCode == 401) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Неверное имя пользователя или пароль');
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Неверный запрос');
      } else if (response.statusCode == 403) {
        throw Exception('Доступ запрещен. Проверьте настройки безопасности');
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      print('Error in login: $e');
      rethrow;
    }
  }
  
  Future<bool> testConnection() async {
    try {
      print('Testing connection to: $baseUrl/auth/test');
      final response = await http.get(
        Uri.parse('$baseUrl/auth/test'),
      ).timeout(const Duration(seconds: 5));
      
      print('Test connection status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }
}
