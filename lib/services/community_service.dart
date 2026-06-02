import 'dart:convert';

import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/community_review.dart';
import 'package:ebookreader/models/favorite_quote.dart';
import 'package:http/http.dart' as http;

class CommunityService {
  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<List<CommunityReview>> getReviews(
    String token,
    int bookId, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/reviews?limit=$limit',
      ),
      headers: _headers(token),
    );
    _throwIfError(response, 'Ошибка загрузки отзывов');
    final reviews = _decodeList(
      response.body,
    ).map((item) => CommunityReview.fromJson(item)).toList();
    reviews.sort(_compareReviewRank);
    return reviews;
  }

  Future<CommunityReview> saveReview({
    required String token,
    required int bookId,
    required int rating,
    required String text,
  }) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/user/books/$bookId/reviews'),
      headers: _headers(token),
      body: json.encode({'rating': rating, 'text': text}),
    );
    _throwIfError(response, 'Ошибка сохранения отзыва');
    return CommunityReview.fromJson(json.decode(response.body));
  }

  Future<void> createReply({
    required String token,
    required int bookId,
    required int reviewId,
    required String text,
    int? parentReplyId,
  }) async {
    final payload = <String, dynamic>{'text': text};
    if (parentReplyId != null) {
      payload['parentReplyId'] = parentReplyId;
    }
    final response = await http.post(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/reviews/$reviewId/replies',
      ),
      headers: _headers(token),
      body: json.encode(payload),
    );
    _throwIfError(response, 'Ошибка сохранения ответа');
  }

  Future<void> voteReview(
    String token,
    int bookId,
    int reviewId,
    int vote,
  ) async {
    final response = await http.put(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/reviews/$reviewId/vote',
      ),
      headers: _headers(token),
      body: json.encode({'vote': vote.clamp(-1, 1)}),
    );
    _throwIfError(response, 'Ошибка голосования');
  }

  Future<void> voteReply(
    String token,
    int bookId,
    int replyId,
    int vote,
  ) async {
    final response = await http.put(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/reviews/replies/$replyId/vote',
      ),
      headers: _headers(token),
      body: json.encode({'vote': vote.clamp(-1, 1)}),
    );
    _throwIfError(response, 'Ошибка голосования');
  }

  Future<List<FavoriteQuote>> getBookQuotes(
    String token,
    int bookId, {
    int limit = 50,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/quotes?limit=$limit',
      ),
      headers: _headers(token),
    );
    _throwIfError(response, 'Ошибка загрузки цитат');
    final quotes = _decodeList(
      response.body,
    ).map((item) => FavoriteQuote.fromJson(item)).toList();
    quotes.sort(_compareQuoteRank);
    return quotes;
  }

  Future<List<FavoriteQuote>> getMyQuotes(String token) async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}/user/books/quotes/favorites'),
      headers: _headers(token),
    );
    _throwIfError(response, 'Ошибка загрузки цитат');
    return _decodeList(
      response.body,
    ).map((item) => FavoriteQuote.fromJson(item)).toList();
  }

  Future<FavoriteQuote> publishQuote({
    required String token,
    required int bookId,
    required int annotationId,
  }) async {
    final response = await http.post(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/annotations/$annotationId/quote',
      ),
      headers: _headers(token),
    );
    _throwIfError(response, 'Ошибка публикации цитаты');
    return FavoriteQuote.fromJson(json.decode(response.body));
  }

  Future<void> voteQuote(
    String token,
    int bookId,
    int quoteId,
    int vote,
  ) async {
    final response = await http.put(
      Uri.parse(
        '${ApiConstants.baseUrl}/user/books/$bookId/quotes/$quoteId/vote',
      ),
      headers: _headers(token),
      body: json.encode({'vote': vote.clamp(-1, 1)}),
    );
    _throwIfError(response, 'Ошибка голосования');
  }

  List<Map<String, dynamic>> _decodeList(String body) {
    if (body.isEmpty || body == '[]') return [];
    final decoded = json.decode(body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  void _throwIfError(http.Response response, String fallback) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    if (response.body.isNotEmpty) {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['message'] != null) {
        throw Exception(decoded['message']);
      }
    }
    throw Exception('$fallback: ${response.statusCode}');
  }

  int _compareReviewRank(CommunityReview a, CommunityReview b) {
    final scoreCompare = _communityScore(
      b.likes,
      b.dislikes,
    ).compareTo(_communityScore(a.likes, a.dislikes));
    if (scoreCompare != 0) return scoreCompare;
    return b.likes.compareTo(a.likes);
  }

  int _compareQuoteRank(FavoriteQuote a, FavoriteQuote b) {
    final scoreCompare = _communityScore(
      b.likes,
      b.dislikes,
    ).compareTo(_communityScore(a.likes, a.dislikes));
    if (scoreCompare != 0) return scoreCompare;
    return b.likes.compareTo(a.likes);
  }

  double _communityScore(int likes, int dislikes) {
    final totalVotes = likes + dislikes;
    if (totalVotes <= 0) return 0;
    return likes / totalVotes;
  }
}
