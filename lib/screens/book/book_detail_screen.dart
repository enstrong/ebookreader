import 'package:flutter/material.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:ebookreader/screens/reader/reader_screen.dart';
import 'package:ebookreader/screens/audio/audio_player_screen.dart';
import 'package:ebookreader/constants/api_constants.dart';

/// Экран детальной информации о книге.
///
/// Отображает обложку, название, автора, жанр и описание книги,
/// а также список глав с возможностью перехода к чтению.
/// Поддерживает сохранение книги в библиотеку и сохранение прогресса чтения.
class BookDetailScreen extends StatefulWidget {
  final String token;
  final int bookId;

  const BookDetailScreen({
    super.key,
    required this.token,
    required this.bookId,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen>
    with SingleTickerProviderStateMixin {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();

  Map<String, dynamic>? _book;
  List<dynamic> _chapters = [];
  bool _isLoading = true;
  bool _isBookmarked = false;
  int _currentChapter = 1;
  double _segmentProgress = 0.0;
  int _audioPositionMs = 0;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _loadBookDetails();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadBookDetails() async {
    try {
      final book = await _bookService.getBookById(widget.token, widget.bookId);
      final chapters = await _bookService.getBookChapters(widget.token, widget.bookId);
      final progress = await _bookmarkService.getProgress(
        widget.token,
        widget.bookId,
      );

      setState(() {
        _book = book;
        _chapters = chapters;
        _currentChapter = progress['segmentOrder'] ?? progress['currentChapter'] ?? 1;
        _segmentProgress = _asDouble(progress['segmentProgress']);
        _audioPositionMs = _asInt(progress['audioPositionMs']);
        _isBookmarked = progress['isBookmarked'] ?? false;
        _isLoading = false;
      });
      _animController.forward();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Ошибка загрузки: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _toggleBookmark() async {
    try {
      if (_isBookmarked) {
        await _bookmarkService.removeBookmark(widget.token, widget.bookId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.library_add_check_outlined, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Удалено из сохранённых'),
                ],
              ),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        await _bookmarkService.addBookmark(widget.token, widget.bookId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.library_add_check, color: Colors.white),
                  SizedBox(width: 12),
                  Text('Книга сохранена'),
                ],
              ),
              backgroundColor: Colors.green.shade600,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
      setState(() => _isBookmarked = !_isBookmarked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    }
  }

  void _openReader(int chapterOrder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          token: widget.token,
          bookId: widget.bookId,
          chapterOrder: chapterOrder,
          initialSegmentProgress: chapterOrder == _currentChapter ? _segmentProgress : 0.0,
        ),
      ),
    ).then((_) => _loadBookDetails());
  }

  void _openAudioPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioPlayerScreen(
          token: widget.token,
          bookId: widget.bookId,
          title: _book?['title'] ?? 'Без названия',
          author: _book?['author'] ?? '',
          initialSegmentOrder: _currentChapter,
          initialSegmentProgress: _segmentProgress,
          initialAudioPositionMs: _audioPositionMs,
        ),
      ),
    ).then((_) => _loadBookDetails());
  }

  bool get _hasText {
    final availability = (_book?['availability'] ?? 'METADATA_ONLY').toString();
    return availability == 'TEXT' || availability == 'SYNCED';
  }

  bool get _hasAudio {
    final availability = (_book?['availability'] ?? 'METADATA_ONLY').toString();
    return availability == 'AUDIO' || availability == 'SYNCED';
  }

  String _availabilityLabel() {
    final availability = (_book?['availability'] ?? 'METADATA_ONLY').toString();
    switch (availability) {
      case 'TEXT':
        return 'Есть текст';
      case 'AUDIO':
        return 'Есть аудио';
      case 'SYNCED':
        return 'Текст + аудио';
      case 'PDF_ONLY':
        return 'PDF без синхронизации';
      default:
        return 'Метаданные';
    }
  }

  double _asDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble().clamp(0.0, 1.0).toDouble();
    return (double.tryParse(value.toString()) ?? 0.0).clamp(0.0, 1.0).toDouble();
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        body: Center(
          child: CircularProgressIndicator(
            color: const Color(0xFF14FFEC),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_book == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0E27),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Ошибка'),
        ),
        body: const Center(
          child: Text('Книга не найдена', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isBookmarked ? Icons.library_add_check : Icons.library_add_outlined,
                color: _isBookmarked ? const Color(0xFF14FFEC) : Colors.white,
              ),
            ),
            onPressed: _toggleBookmark,
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF0A0E27),
                const Color(0xFF1A1F3A),
              ],
            ),
          ),
          child: CustomScrollView(
            slivers: [
              // Hero cover
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.only(top: 120, bottom: 30),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'book-${widget.bookId}',
                        child: Container(
                          width: 200,
                          height: 300,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF14FFEC).withValues(alpha: 0.2),
                                blurRadius: 40,
                                spreadRadius: 5,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: _book!['coverUrl'] != null && _book!['coverUrl'].toString().isNotEmpty
                                ? Image.network(
                                    ApiConstants.getCoverUrl(_book!['coverUrl']),
                                    fit: BoxFit.cover,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: Colors.white.withValues(alpha: 0.03),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            color: const Color(0xFF14FFEC),
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      debugPrint('❌ Ошибка загрузки обложки: $error');
                                      debugPrint('📍 URL: ${ApiConstants.getCoverUrl(_book!['coverUrl'])}');
                                      return _buildPlaceholder();
                                    },
                                  )
                                : _buildPlaceholder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              _book!['title'] ?? 'Без названия',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _book!['author'] ?? 'Неизвестный автор',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (_detailGenres().isNotEmpty)
                                  for (final genre in _detailGenres().take(2))
                                    _buildInfoChip(genre),
                                _buildLanguageChip(_bookLanguage()),
                                _buildInfoChip(_availabilityLabel()),
                                if (_bookPages() > 0)
                                  _buildInfoChip('${_bookPages()} стр.'),
                                if ((_book!['average_rating'] ?? _book!['averageRating'] ?? 0) != 0)
                                  _buildInfoChip('${(_book!['average_rating'] ?? _book!['averageRating']).toString()} ★'),
                                if ((_book!['ratings_count'] ?? _book!['ratingsCount'] ?? 0) != 0)
                                  _buildInfoChip('${(_book!['ratings_count'] ?? _book!['ratingsCount']).toString()} оценок'),
                                _buildInfoChip(_chapters.isEmpty ? 'Нет глав' : '${_chapters.length} глав'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.menu_book_rounded,
                          label: _currentChapter > 1
                              ? 'Читать $_currentChapter сегм.'
                              : 'Читать',
                          enabled: _hasText && _chapters.isNotEmpty,
                          onPressed: () => _openReader(_currentChapter),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.headphones_rounded,
                          label: 'Слушать',
                          enabled: _hasAudio,
                          onPressed: _openAudioPlayer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 56,
                        width: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.1),
                              Colors.white.withValues(alpha: 0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1.5,
                          ),
                        ),
                        child: IconButton(
                          onPressed: _toggleBookmark,
                          icon: Icon(
                            _isBookmarked ? Icons.library_add_check : Icons.library_add_outlined,
                            color: _isBookmarked ? const Color(0xFF14FFEC) : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Description
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Описание',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _book!['description'] ?? 'Описание отсутствует',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Главы',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF14FFEC).withValues(alpha: 0.2),
                                  const Color(0xFF0D7377).withValues(alpha: 0.1),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_chapters.length} глав',
                              style: const TextStyle(
                                color: Color(0xFF14FFEC),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Chapters list
              _chapters.isNotEmpty
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final chapter = _chapters[index];
                          final chapterNum = chapter['chapterOrder'];
                          final isCurrent = chapterNum == _currentChapter;

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: isCurrent
                                  ? const LinearGradient(
                                      colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.05),
                                        Colors.white.withValues(alpha: 0.02),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isCurrent
                                    ? Colors.transparent
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 1.5,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    '$chapterNum',
                                    style: TextStyle(
                                      color: isCurrent
                                          ? Colors.white
                                          : const Color(0xFF14FFEC),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                chapter['title'] ?? 'Глава $chapterNum',
                                style: TextStyle(
                                  color: isCurrent
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Icon(
                                isCurrent
                                    ? Icons.play_circle_filled_rounded
                                    : Icons.arrow_forward_ios_rounded,
                                color: isCurrent
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.4),
                                size: isCurrent ? 24 : 16,
                              ),
                              onTap: () => _openReader(chapterNum),
                            ),
                          );
                        },
                        childCount: _chapters.length,
                      ),
                    )
                  : SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 40),
                        child: Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF14FFEC)
                                      .withValues(alpha: 0.1),
                                ),
                                child: const Icon(
                                  Icons.menu_book_outlined,
                                  size: 60,
                                  color: Color(0xFF14FFEC),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Главы отсутствуют',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Эта книга пока не содержит глав для чтения',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.5),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _detailGenres() {
    final raw = _book!['genres'] ?? _book!['genre'];
    if (raw == null) return [];
    if (raw is String) {
      return raw
          .split(';')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    if (raw is List) {
      return raw
          .map((item) {
            if (item is String) return item;
            if (item is Map && item.containsKey('name')) return item['name']?.toString() ?? '';
            return item.toString();
          })
          .where((value) => value.isNotEmpty)
          .toList();
    }
    return [raw.toString()];
  }

  String _bookLanguage() {
    final raw = _book!['language'] ?? _book!['languageCode'] ?? _book!['language_code'];
    if (raw == null || raw.toString().trim().isEmpty) {
      return 'не указан';
    }
    return _languageLabel(raw.toString());
  }

  String _languageLabel(String code) {
    final normalized = code.trim().toLowerCase();
    switch (normalized) {
      case 'en':
      case 'eng':
      case 'en-us':
      case 'en-gb':
      case 'english':
        return 'English';
      case 'ru':
      case 'rus':
      case 'русский':
      case 'russian':
        return 'Русский';
      case 'es':
      case 'spa':
      case 'español':
      case 'spanish':
        return 'Español';
      case 'fr':
      case 'fra':
      case 'fre':
      case 'français':
      case 'french':
        return 'Français';
      case 'de':
      case 'ger':
      case 'deu':
      case 'deutsch':
      case 'german':
        return 'Deutsch';
      case 'it':
      case 'ita':
      case 'italiano':
      case 'italian':
        return 'Italiano';
      case 'pt':
      case 'por':
      case 'português':
      case 'portuguese':
        return 'Português';
      case 'ar':
      case 'ara':
      case 'arabic':
        return 'العربية';
      case 'fa':
      case 'fas':
      case 'per':
      case 'persian':
        return 'فارسی';
      case 'pl':
      case 'pol':
      case 'polish':
        return 'Polski';
      case 'ja':
      case 'jpn':
      case 'japanese':
        return '日本語';
      case 'ko':
      case 'kor':
      case 'korean':
        return '한국어';
      case 'zh':
      case 'zho':
      case 'chi':
      case 'chinese':
      case '中文':
        return '中文';
      default:
        return normalized
            .split(RegExp(r'[_\-\s]+'))
            .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
            .join(' ');
    }
  }

  int _bookPages() {
    final raw = _book!['page_count'] ?? _book!['pageCount'] ?? _book!['num_pages'];
    if (raw == null) return 0;
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? 0;
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: enabled
            ? const LinearGradient(colors: [Color(0xFF14FFEC), Color(0xFF0D7377)])
            : LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        border: enabled
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1.5),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.28),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildLanguageChip(String language) {
    final flag = _languageFlag(_bookLanguageCode());
    final display = 'Язык: $language';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flag != null) ...[
            Container(
              height: 18,
              width: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              alignment: Alignment.center,
              child: Text(
                flag,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            display,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String? _languageFlag(String code) {
    switch (code.trim().toLowerCase()) {
      case 'en':
      case 'eng':
      case 'en-us':
      case 'en-gb':
      case 'english':
        return '🇬🇧';
      case 'ru':
      case 'rus':
      case 'русский':
      case 'russian':
        return '🇷🇺';
      case 'es':
      case 'spa':
      case 'español':
      case 'spanish':
        return '🇪🇸';
      case 'fr':
      case 'fra':
      case 'fre':
      case 'français':
      case 'french':
        return '🇫🇷';
      case 'de':
      case 'ger':
      case 'deu':
      case 'deutsch':
      case 'german':
        return '🇩🇪';
      case 'it':
      case 'ita':
      case 'italiano':
      case 'italian':
        return '🇮🇹';
      case 'pt':
      case 'por':
      case 'português':
      case 'portuguese':
        return '🇵🇹';
      case 'ar':
      case 'ara':
      case 'arabic':
        return '🇸🇦';
      case 'fa':
      case 'fas':
      case 'per':
      case 'persian':
        return '🇮🇷';
      case 'pl':
      case 'pol':
      case 'polish':
        return '🇵🇱';
      case 'ja':
      case 'jpn':
      case 'japanese':
        return '🇯🇵';
      case 'ko':
      case 'kor':
      case 'korean':
        return '🇰🇷';
      case 'zh':
      case 'zho':
      case 'chi':
      case 'chinese':
      case '中文':
        return '🇨🇳';
      default:
        return null;
    }
  }

  String _bookLanguageCode() {
    final raw = _book!['language'] ?? _book!['languageCode'] ?? _book!['language_code'];
    if (raw == null) return '';
    return raw.toString().trim().toLowerCase();
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.book_rounded,
          size: 80,
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}
