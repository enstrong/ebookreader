class BookAnnotation {
  final int id;
  final int bookId;
  final int chapterOrder;
  final int startOffset;
  final int endOffset;
  final String highlightedText;
  final String note;
  final String color;

  const BookAnnotation({
    required this.id,
    required this.bookId,
    required this.chapterOrder,
    required this.startOffset,
    required this.endOffset,
    required this.highlightedText,
    required this.note,
    required this.color,
  });

  factory BookAnnotation.fromJson(Map<String, dynamic> json) {
    return BookAnnotation(
      id: _asInt(json['id']),
      bookId: _asInt(json['bookId']),
      chapterOrder: _asInt(json['chapterOrder']),
      startOffset: _asInt(json['startOffset']),
      endOffset: _asInt(json['endOffset']),
      highlightedText: json['highlightedText']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      color: json['color']?.toString() ?? '#14FFEC',
    );
  }

  BookAnnotation copyWith({
    String? note,
    String? color,
  }) {
    return BookAnnotation(
      id: id,
      bookId: bookId,
      chapterOrder: chapterOrder,
      startOffset: startOffset,
      endOffset: endOffset,
      highlightedText: highlightedText,
      note: note ?? this.note,
      color: color ?? this.color,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
