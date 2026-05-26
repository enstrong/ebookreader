import 'package:flutter_test/flutter_test.dart';
import 'package:ebookreader/models/book.dart';
import 'package:ebookreader/models/community_review.dart';
import 'package:ebookreader/models/favorite_quote.dart';
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

  group('Community Model Tests', () {
    test('CommunityReview.fromJson parses replies and votes', () {
      final review = CommunityReview.fromJson({
        'id': 7,
        'bookId': 2,
        'rating': 5,
        'text': 'Great book',
        'nickname': 'reader',
        'avatarInitial': 'R',
        'likes': 3,
        'dislikes': 1,
        'currentUserVote': 1,
        'currentUserReview': true,
        'replies': [
          {
            'id': 9,
            'text': 'agree',
            'nickname': 'other',
            'avatarInitial': 'O',
            'likes': 1,
            'dislikes': 0,
            'currentUserVote': 0,
            'replies': [],
          },
        ],
      });

      expect(review.id, 7);
      expect(review.rating, 5);
      expect(review.currentUserReview, isTrue);
      expect(review.replies.single.text, 'agree');
    });

    test('FavoriteQuote.fromJson parses quote metadata', () {
      final quote = FavoriteQuote.fromJson({
        'id': 4,
        'bookId': 2,
        'bookTitle': 'Book',
        'bookAuthor': 'Author',
        'text': 'A line worth saving.',
        'chapterOrder': 3,
        'nickname': 'reader',
        'avatarInitial': 'R',
        'likes': 8,
        'dislikes': 2,
        'currentUserVote': -1,
        'currentUserQuote': false,
      });

      expect(quote.id, 4);
      expect(quote.chapterOrder, 3);
      expect(quote.currentUserVote, -1);
      expect(quote.text, contains('saving'));
    });
  });
}
