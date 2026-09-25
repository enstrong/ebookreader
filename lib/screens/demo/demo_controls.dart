import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/api_constants.dart';
import '../../services/audiobook_playback_service.dart';
import 'demo_start_screen.dart';
import 'demo_upload_screen.dart';

class DemoControls extends StatelessWidget implements PreferredSizeWidget {
  final String token;
  const DemoControls({super.key, required this.token});
  @override
  Size get preferredSize => const Size.fromHeight(58);
  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    title: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live demo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          'Private session · expires in 24h',
          style: TextStyle(fontSize: 11),
        ),
      ],
    ),
    actions: [
      IconButton(
        tooltip: 'Upload a book',
        icon: const Icon(Icons.upload_file),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DemoUploadScreen(token: token)),
          );
        },
      ),
      IconButton(
        tooltip: 'Reset demo',
        icon: const Icon(Icons.restart_alt),
        onPressed: () => resetDemo(context, token),
      ),
    ],
  );
}

Future<void> resetDemo(BuildContext context, String token) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Start a fresh demo?'),
      content: const Text(
        'This deletes your temporary uploads, notes, ratings and progress, then creates a fresh sample library.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep exploring'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reset demo'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    final response = await http
        .delete(
          Uri.parse('${ApiConstants.baseUrl}/demo/session'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (![204, 401, 403].contains(response.statusCode))
      throw Exception('Reset failed');
    await AudiobookPlaybackService.instance.player.stop();
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'token',
      'role',
      'username',
      'email',
      'demo_token',
      'demo_expires_at',
    ]) {
      await prefs.remove(key);
    }
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DemoStartScreen()),
      (_) => false,
    );
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reset. Please try again.')),
      );
  }
}
