import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/api_constants.dart';
import '../user/user_home.dart';

/// Restores a visitor's isolated demo or creates one automatically on first visit.
class DemoStartScreen extends StatefulWidget {
  const DemoStartScreen({super.key});
  @override
  State<DemoStartScreen> createState() => _DemoStartScreenState();
}

class _DemoStartScreenState extends State<DemoStartScreen> {
  String? _token;
  String? _error;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('demo_token');
      final uri = Uri.parse('${ApiConstants.baseUrl}/demo/session');
      http.Response? response;
      if (saved != null) {
        response = await http
            .get(uri, headers: {'Authorization': 'Bearer $saved'})
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 &&
            response.statusCode != 401 &&
            response.statusCode != 403) {
          throw Exception('Demo temporarily unavailable. Please retry.');
        }
      }
      if (response == null || response.statusCode != 200) {
        response = await http.post(uri).timeout(const Duration(seconds: 30));
      }
      if (response.statusCode != 200) {
        throw Exception(
          response.statusCode == 429
              ? 'The demo is busy. Please try again in a few minutes.'
              : 'Could not start the demo. Please retry.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      for (final key in [
        'token',
        'username',
        'email',
        'role',
        'authProvider',
      ]) {
        await prefs.setString(key, data[key] as String);
      }
      await prefs.setString('demo_token', data['token'] as String);
      await prefs.setString('demo_expires_at', data['expiresAt'] as String);
      if (mounted) setState(() => _token = data['token'] as String);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_token != null) return UserHome(token: _token!);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_stories_rounded, size: 56),
              const SizedBox(height: 24),
              Text(
                _error == null ? 'Preparing your private library…' : _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_error == null)
                const CircularProgressIndicator()
              else
                FilledButton(onPressed: _start, child: const Text('Retry')),
              const SizedBox(height: 20),
              const Text(
                'No registration. Your changes and uploads expire after 24 hours.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
