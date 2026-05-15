class AudioTrack {
  final int id;
  final int segmentOrder;
  final String title;
  final int durationMs;
  final String streamUrl;
  final String contentType;

  AudioTrack({
    required this.id,
    required this.segmentOrder,
    required this.title,
    required this.durationMs,
    required this.streamUrl,
    required this.contentType,
  });

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    return AudioTrack(
      id: _asInt(json['id']),
      segmentOrder: _asInt(json['segmentOrder'] ?? json['chapterOrder']),
      title: (json['title'] ?? 'Сегмент').toString(),
      durationMs: _asInt(json['durationMs']),
      streamUrl: (json['streamUrl'] ?? '').toString(),
      contentType: (json['contentType'] ?? 'audio/mpeg').toString(),
    );
  }

  static int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }
}
