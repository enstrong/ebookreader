class CommunityReview {
  final int id;
  final int bookId;
  final int rating;
  final String text;
  final String nickname;
  final String avatarInitial;
  final int likes;
  final int dislikes;
  final int currentUserVote;
  final bool currentUserReview;
  final List<CommunityReply> replies;

  const CommunityReview({
    required this.id,
    required this.bookId,
    required this.rating,
    required this.text,
    required this.nickname,
    required this.avatarInitial,
    required this.likes,
    required this.dislikes,
    required this.currentUserVote,
    required this.currentUserReview,
    required this.replies,
  });

  factory CommunityReview.fromJson(Map<String, dynamic> json) {
    return CommunityReview(
      id: _asInt(json['id']),
      bookId: _asInt(json['bookId']),
      rating: _asInt(json['rating']).clamp(0, 5).toInt(),
      text: json['text']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? 'User',
      avatarInitial: json['avatarInitial']?.toString() ?? 'U',
      likes: _asInt(json['likes']),
      dislikes: _asInt(json['dislikes']),
      currentUserVote: _asInt(json['currentUserVote']).clamp(-1, 1).toInt(),
      currentUserReview: json['currentUserReview'] == true,
      replies: _asList(
        json['replies'],
      ).map((item) => CommunityReply.fromJson(item)).toList(),
    );
  }
}

class CommunityReply {
  final int id;
  final String text;
  final String nickname;
  final String avatarInitial;
  final int likes;
  final int dislikes;
  final int currentUserVote;
  final List<CommunityReply> replies;

  const CommunityReply({
    required this.id,
    required this.text,
    required this.nickname,
    required this.avatarInitial,
    required this.likes,
    required this.dislikes,
    required this.currentUserVote,
    required this.replies,
  });

  factory CommunityReply.fromJson(Map<String, dynamic> json) {
    return CommunityReply(
      id: _asInt(json['id']),
      text: json['text']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? 'User',
      avatarInitial: json['avatarInitial']?.toString() ?? 'U',
      likes: _asInt(json['likes']),
      dislikes: _asInt(json['dislikes']),
      currentUserVote: _asInt(json['currentUserVote']).clamp(-1, 1).toInt(),
      replies: _asList(
        json['replies'],
      ).map((item) => CommunityReply.fromJson(item)).toList(),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _asList(dynamic value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
