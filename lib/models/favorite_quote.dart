class FavoriteQuote {
  final int id;
  final int bookId;
  final String bookTitle;
  final String bookAuthor;
  final String text;
  final int chapterOrder;
  final String nickname;
  final String avatarInitial;
  final int likes;
  final int dislikes;
  final int currentUserVote;
  final bool currentUserQuote;

  const FavoriteQuote({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.bookAuthor,
    required this.text,
    required this.chapterOrder,
    required this.nickname,
    required this.avatarInitial,
    required this.likes,
    required this.dislikes,
    required this.currentUserVote,
    required this.currentUserQuote,
  });

  factory FavoriteQuote.fromJson(Map<String, dynamic> json) {
    return FavoriteQuote(
      id: _asInt(json['id']),
      bookId: _asInt(json['bookId']),
      bookTitle: json['bookTitle']?.toString() ?? '',
      bookAuthor: json['bookAuthor']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      chapterOrder: _asInt(json['chapterOrder']),
      nickname: json['nickname']?.toString() ?? 'User',
      avatarInitial: json['avatarInitial']?.toString() ?? 'U',
      likes: _asInt(json['likes']),
      dislikes: _asInt(json['dislikes']),
      currentUserVote: _asInt(json['currentUserVote']).clamp(-1, 1).toInt(),
      currentUserQuote: json['currentUserQuote'] == true,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
