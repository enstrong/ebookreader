String genreLabel(String genre) {
  final normalized = genre.trim().toLowerCase();
  switch (normalized) {
    case 'fiction':
      return 'Художественная литература';
    case 'fantasy':
    case 'fantasy, paranormal':
    case 'fantasy-paranormal':
      return 'Фэнтези и мистика';
    case 'young-adult':
    case 'young adult':
      return 'Подростковая литература';
    case 'children':
      return 'Детская литература';
    case 'romance':
      return 'Романтика';
    case 'mystery, thriller, crime':
    case 'mystery-thriller-crime':
    case 'mystery':
      return 'Детективы и триллеры';
    case 'history, historical fiction, biography':
    case 'history-biography':
      return 'История и биографии';
    case 'comics, graphic':
    case 'comics-graphic':
      return 'Комиксы и графические романы';
    case 'poetry':
      return 'Поэзия';
    case 'non-fiction':
    case 'nonfiction':
      return 'Нон-фикшн';
    case 'classics':
      return 'Классика';
    case 'science fiction':
    case 'sci-fi':
      return 'Научная фантастика';
    case 'horror':
      return 'Ужасы';
    case 'adventure':
      return 'Приключения';
    case 'drama':
      return 'Драма';
    case 'literature':
      return 'Литература';
    default:
      return genre
          .split(RegExp(r'[_\-\s,]+'))
          .where((word) => word.trim().isNotEmpty)
          .map((word) => word.trim())
          .join(' ');
  }
}

String authorLabel(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return 'Неизвестный автор';
  final numericOnly = RegExp(r'^[\d,\s|]+$').hasMatch(raw);
  if (numericOnly) {
    final ids = raw
        .split(RegExp(r'[,|\s]+'))
        .where((part) => part.trim().isNotEmpty);
    for (final id in ids) {
      final name = _knownAuthorIds[id.trim()];
      if (name != null) return name;
    }
  }
  return numericOnly ? 'Неизвестный автор' : raw;
}

const Map<String, String> _knownAuthorIds = {
  '1265': 'Jane Austen',
  '1036615': 'Charlotte Bronte',
  '1244': 'Mark Twain',
  '11139': 'Mary Shelley',
  '903': 'Homer',
  '239579': 'Charles Dickens',
  '6988': 'Bram Stoker',
  '3565': 'Oscar Wilde',
  '4785': 'Alexandre Dumas',
  '3137322': 'Fyodor Dostoevsky',
  '1624': 'Herman Melville',
  '128382': 'Leo Tolstoy',
  '8164': 'Lewis Carroll',
  '4191': 'Emily Bronte',
  '1315': 'Louisa May Alcott',
};
