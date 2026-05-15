import 'package:flutter_test/flutter_test.dart';
import 'package:ebookreader/models/book.dart';
import 'package:ebookreader/models/user.dart';

void main() {
  group('Book Model Tests', () {
    test('Book.fromJson should create a valid Book object', () {
      final json = {
        'id': 1,
        'title': 'Test Book',
        'author': 'Test Author',
        'description': 'Test Description',
        'fileUrl': 'http://example.com/file.epub',
        'coverUrl': 'http://example.com/cover.jpg',
        'availability': 'SYNCED',
      };

      final book = Book.fromJson(json);

      expect(book.id, 1);
      expect(book.title, 'Test Book');
      expect(book.author, 'Test Author');
      expect(book.description, 'Test Description');
      expect(book.fileUrl, 'http://example.com/file.epub');
      expect(book.coverUrl, 'http://example.com/cover.jpg');
      expect(book.availability, 'SYNCED');
      expect(book.hasText, isTrue);
      expect(book.hasAudio, isTrue);
    });
  });

  group('User Model Tests', () {
    test('User.fromJson should create a valid User object', () {
      final json = {
        'id': 1,
        'username': 'testuser',
        'email': 'test@example.com',
        'role': 'USER',
      };

      final user = User.fromJson(json);

      expect(user.id, 1);
      expect(user.username, 'testuser');
      expect(user.email, 'test@example.com');
      expect(user.role, 'USER');
    });
  });
}
