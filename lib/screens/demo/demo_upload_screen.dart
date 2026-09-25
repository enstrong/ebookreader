import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../constants/api_constants.dart';
import '../book/book_detail_screen.dart';

class DemoUploadScreen extends StatefulWidget {
  final String token;
  const DemoUploadScreen({super.key, required this.token});
  @override
  State<DemoUploadScreen> createState() => _DemoUploadScreenState();
}

class _DemoUploadScreenState extends State<DemoUploadScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'fb2', 'txt'],
        withData: true,
      );
      if (result == null) return;
      final file = result.files.single;
      if (file.size > 10 * 1024 * 1024 || file.bytes == null) {
        throw Exception('Choose a book smaller than 10 MB.');
      }
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('${ApiConstants.baseUrl}/demo/uploads'),
            )
            ..headers['Authorization'] = 'Bearer ${widget.token}'
            ..files.add(
              http.MultipartFile.fromBytes(
                'file',
                file.bytes!,
                filename: file.name,
              ),
            );
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 60)),
      );
      if (response.statusCode != 200) {
        throw Exception(
          response.statusCode == 429
              ? 'Demo upload limit reached. Reset the demo to start fresh.'
              : response.statusCode == 401
              ? 'Your demo expired. Open the demo link again.'
              : 'Upload failed. Please try a smaller book.',
        );
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['error'] != null) throw Exception(data['error']);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(
            token: widget.token,
            bookId: (data['id'] as num).toInt(),
          ),
        ),
      );
    } catch (e) {
      if (mounted)
        setState(() => _message = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Upload a book')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.upload_file_rounded, size: 64),
              const SizedBox(height: 24),
              const Text(
                'Try reading your own book',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'EPUB, FB2 or UTF-8 TXT · up to 10 MB\n10 books and 20 MB total per visitor.\n\nYour upload, reading progress and notes are private to this browser’s demo session and deleted after 24 hours.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_busy)
                const CircularProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _upload,
                  icon: const Icon(Icons.add),
                  label: const Text('Choose a book'),
                ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
