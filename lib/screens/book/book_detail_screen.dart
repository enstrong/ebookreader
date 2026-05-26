import 'package:flutter/material.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:ebookreader/services/recommendation_service.dart';
import 'package:ebookreader/services/user_service.dart';
import 'package:ebookreader/screens/reader/reader_screen.dart';
import 'package:ebookreader/screens/audio/audio_player_screen.dart';
import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:ebookreader/utils/book_display.dart';
import 'package:ebookreader/widgets/book_community_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final UserService _userService = UserService();
  final RecommendationService _recommendationService = RecommendationService();

  Map<String, dynamic>? _book;
  List<dynamic> _chapters = [];
  bool _isLoading = true;
  bool _isBookmarked = false;
  bool _audioSubscriptionActive = false;
  bool _isSubscriptionSaving = false;
  bool _isRatingSaving = false;
  bool _isMarkReadSaving = false;
  bool _isSimilarLoading = false;
  int _userRating = 0;
  String _readingStatus = 'WANT_TO_READ';
  List<dynamic> _similarBooks = [];
  int _currentChapter = 1;
  double _segmentProgress = 0.0;
  int _audioPositionMs = 0;
  String _lastProgressMode = 'TEXT';
  String _selectedDetailSection = 'chapters';
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
      final chapters = await _bookService.getBookChapters(
        widget.token,
        widget.bookId,
      );
      final progress = await _bookmarkService.getProgress(
        widget.token,
        widget.bookId,
      );
      final profile = await _userService.getProfile(widget.token);

      setState(() {
        _book = book;
        _chapters = chapters;
        _audioSubscriptionActive = profile['audioSubscriptionActive'] == true;
        _currentChapter =
            progress['segmentOrder'] ?? progress['currentChapter'] ?? 1;
        _segmentProgress = _asDouble(progress['segmentProgress']);
        _audioPositionMs = _asInt(progress['audioPositionMs']);
        _lastProgressMode = (progress['lastMode'] ?? 'TEXT').toString();
        _isBookmarked = progress['isBookmarked'] ?? false;
        _userRating = _asRating(progress['rating']);
        _readingStatus = (progress['status'] ?? 'WANT_TO_READ').toString();
        _isLoading = false;
      });
      if (_userRating >= 4) {
        _loadSimilarBooks();
      }
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
      setState(() => _isBookmarked = !_isBookmarked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
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
          initialSegmentProgress: chapterOrder == _currentChapter
              ? _segmentProgress
              : 0.0,
          initialRating: _userRating,
        ),
      ),
    ).then((_) => _loadBookDetails());
  }

  Future<void> _saveRating(int rating) async {
    if (_isRatingSaving || !_isMarkedRead || rating < 1 || rating > 5) return;
    final previous = _userRating;
    final nextRating = previous == rating ? 0 : rating;
    setState(() {
      _userRating = nextRating;
      _isRatingSaving = true;
    });

    try {
      final savedRating = await _bookmarkService.updateRating(
        widget.token,
        widget.bookId,
        nextRating,
      );
      if (!mounted) return;
      setState(() {
        _userRating = savedRating;
        _isRatingSaving = false;
      });
      if (savedRating >= 4) {
        _loadSimilarBooks();
      } else {
        setState(() => _similarBooks = []);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedRating == 0 ? 'Оценка удалена' : 'Оценка сохранена',
          ),
          backgroundColor: context.palette.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userRating = previous;
        _isRatingSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сохранения оценки: $e'),
          backgroundColor: context.palette.danger,
        ),
      );
    }
  }

  bool get _isMarkedRead => _readingStatus.toUpperCase() == 'FINISHED';

  Future<void> _markAsRead() async {
    if (_isMarkReadSaving) return;
    setState(() => _isMarkReadSaving = true);
    try {
      final result = await _bookmarkService.markAsRead(
        widget.token,
        widget.bookId,
      );
      if (!mounted) return;
      setState(() {
        _readingStatus = (result['status'] ?? 'FINISHED').toString();
        _userRating = _asRating(result['rating']);
        _isMarkReadSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Книга отмечена как прочитанная'),
          backgroundColor: context.palette.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isMarkReadSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отметки книги: $e'),
          backgroundColor: context.palette.danger,
        ),
      );
    }
  }

  Future<void> _selectDetailSection(String section) async {
    if (section == 'chapters') {
      setState(() => _selectedDetailSection = section);
      return;
    }

    final allowed = await _ensureSpoilersAcknowledged(section);
    if (!allowed || !mounted) return;
    setState(() => _selectedDetailSection = section);
  }

  Future<bool> _ensureSpoilersAcknowledged(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'book_spoilers_acknowledged_${widget.bookId}';
    if (prefs.getBool(key) == true) return true;
    if (!mounted) return false;

    final confirmed = await _showSpoilerGate(kind);
    if (confirmed == true) {
      await prefs.setBool(key, true);
      return true;
    }
    return false;
  }

  Future<bool?> _showSpoilerGate(String kind) async {
    final palette = context.palette;
    final title = kind == 'reviews' ? 'Отзывы' : 'Цитаты';
    bool acknowledged = false;
    bool armed = false;

    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            decoration: BoxDecoration(
              color: palette.elevated,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: palette.border),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '$title могут содержать спойлеры',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Здесь читатели обсуждают конкретные моменты книги. Откройте этот раздел только если точно готовы.',
                    style: TextStyle(color: palette.mutedText, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  CheckboxListTile(
                    value: acknowledged,
                    onChanged: (value) => setModalState(() {
                      acknowledged = value == true;
                      armed = false;
                    }),
                    contentPadding: EdgeInsets.zero,
                    activeColor: palette.accent,
                    title: Text(
                      'Я понимаю, что здесь будут спойлеры',
                      style: TextStyle(color: palette.text),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            'Не открывать',
                            style: TextStyle(color: palette.mutedText),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: acknowledged
                              ? () {
                                  if (!armed) {
                                    setModalState(() => armed = true);
                                    return;
                                  }
                                  Navigator.pop(context, true);
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: armed
                                ? palette.danger
                                : palette.accent,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            armed ? 'Открыть всё равно' : 'Продолжить',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadSimilarBooks() async {
    if (_isSimilarLoading) return;
    setState(() => _isSimilarLoading = true);
    try {
      final similar = await _recommendationService.getSimilarBooks(
        widget.token,
        widget.bookId,
        limit: 4,
      );
      if (!mounted) return;
      setState(() {
        _similarBooks = similar;
        _isSimilarLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSimilarLoading = false);
    }
  }

  Future<void> _openAudioPlayer() async {
    if (!_isDemoAudiobook && !_audioSubscriptionActive) {
      final activated = await _showAudioPaywall();
      if (!activated || !mounted) return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioPlayerScreen(
          token: widget.token,
          bookId: widget.bookId,
          title: _book?['title'] ?? 'Без названия',
          author: authorLabel(_book?['author']),
          coverUrl: _book?['coverUrl']?.toString() ?? '',
          initialSegmentOrder: _currentChapter,
          initialSegmentProgress: _segmentProgress,
          initialAudioPositionMs: _audioPositionMs,
          initialLastMode: _lastProgressMode,
        ),
      ),
    ).then((_) => _loadBookDetails());
  }

  Future<bool> _showAudioPaywall() async {
    final palette = context.palette;
    final shouldActivate = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: palette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Audio Premium',
                style: TextStyle(color: palette.text),
              ),
            ),
          ],
        ),
        content: Text(
          'Аудиокниги доступны по подписке. Для демо можно активировать доступ без оплаты.',
          style: TextStyle(color: palette.text.withValues(alpha: 0.78)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Позже', style: TextStyle(color: palette.mutedText)),
          ),
          FilledButton(
            onPressed: _isSubscriptionSaving
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('Активировать демо'),
          ),
        ],
      ),
    );

    if (shouldActivate != true) {
      return false;
    }

    setState(() => _isSubscriptionSaving = true);
    try {
      final response = await _userService.updateAudioSubscription(
        widget.token,
        true,
      );
      if (!mounted) return false;
      setState(() {
        _audioSubscriptionActive = response['audioSubscriptionActive'] == true;
        _isSubscriptionSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Аудиоподписка активирована'),
          backgroundColor: palette.success,
        ),
      );
      return _audioSubscriptionActive;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isSubscriptionSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка подписки: $e'),
          backgroundColor: palette.danger,
        ),
      );
      return false;
    }
  }

  bool get _hasText {
    final availability = (_book?['availability'] ?? 'METADATA_ONLY').toString();
    return availability == 'TEXT' || availability == 'SYNCED';
  }

  bool get _hasAudio {
    final availability = (_book?['availability'] ?? 'METADATA_ONLY').toString();
    return availability == 'AUDIO' || availability == 'SYNCED';
  }

  bool get _isDemoAudiobook => {
    '269322',
    'pg-ru-21183',
  }.contains((_book?['goodreadsId'] ?? '').toString());

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
    return (double.tryParse(value.toString()) ?? 0.0)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  int _asRating(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value.clamp(0, 5);
    if (value is num) return value.toInt().clamp(0, 5);
    return (int.tryParse(value.toString()) ?? 0).clamp(0, 5);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: palette.background,
        body: Center(
          child: CircularProgressIndicator(
            color: palette.accent,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (_book == null) {
      return Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Ошибка'),
        ),
        body: Center(
          child: Text(
            'Книга не найдена',
            style: TextStyle(color: palette.text),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: palette.elevated.withValues(alpha: 0.80),
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Icon(Icons.arrow_back, color: palette.text),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.elevated.withValues(alpha: 0.80),
                shape: BoxShape.circle,
                border: Border.all(color: palette.border),
              ),
              child: Icon(
                _isBookmarked
                    ? Icons.library_add_check
                    : Icons.library_add_outlined,
                color: _isBookmarked ? palette.accent : palette.text,
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
              colors: [palette.background, palette.surface],
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
                                color: palette.accent.withValues(alpha: 0.2),
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
                            child:
                                _book!['coverUrl'] != null &&
                                    _book!['coverUrl'].toString().isNotEmpty
                                ? Image.network(
                                    ApiConstants.getCoverUrl(
                                      _book!['coverUrl'],
                                    ),
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return Container(
                                            color: Colors.white.withValues(
                                              alpha: 0.03,
                                            ),
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                color: palette.accent,
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          );
                                        },
                                    errorBuilder: (context, error, stackTrace) {
                                      debugPrint(
                                        '❌ Ошибка загрузки обложки: $error',
                                      );
                                      debugPrint(
                                        '📍 URL: ${ApiConstants.getCoverUrl(_book!['coverUrl'])}',
                                      );
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
                              style: TextStyle(
                                color: palette.text,
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
                              authorLabel(_book!['author']),
                              style: TextStyle(
                                color: palette.mutedText,
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
                                    _buildInfoChip(genreLabel(genre)),
                                _buildLanguageChip(_bookLanguage()),
                                _buildInfoChip(_availabilityLabel()),
                                if (_bookPages() > 0)
                                  _buildInfoChip('${_bookPages()} стр.'),
                                if ((_book!['average_rating'] ??
                                        _book!['averageRating'] ??
                                        0) !=
                                    0)
                                  _buildInfoChip(
                                    '${(_book!['average_rating'] ?? _book!['averageRating']).toString()} ★',
                                  ),
                                if ((_book!['ratings_count'] ??
                                        _book!['ratingsCount'] ??
                                        0) !=
                                    0)
                                  _buildInfoChip(
                                    '${(_book!['ratings_count'] ?? _book!['ratingsCount']).toString()} оценок',
                                  ),
                                _buildInfoChip(
                                  _chapters.isEmpty
                                      ? 'Нет глав'
                                      : '${_chapters.length} глав',
                                ),
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
                  child: Column(
                    children: [
                      Row(
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
                              icon: _audioSubscriptionActive || _isDemoAudiobook
                                  ? Icons.headphones_rounded
                                  : Icons.lock_rounded,
                              label:
                                  _audioSubscriptionActive || _isDemoAudiobook
                                  ? 'Слушать'
                                  : 'Premium',
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
                                  palette.text.withValues(alpha: 0.10),
                                  palette.text.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: palette.border,
                                width: 1.5,
                              ),
                            ),
                            child: IconButton(
                              onPressed: _toggleBookmark,
                              icon: Icon(
                                _isBookmarked
                                    ? Icons.library_add_check
                                    : Icons.library_add_outlined,
                                color: _isBookmarked
                                    ? palette.accent
                                    : palette.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _isMarkedRead
                          ? _buildUserRatingPanel()
                          : _buildMarkAsReadButton(),
                      if (_userRating >= 4) ...[
                        const SizedBox(height: 14),
                        _buildMoreLikeThisSection(),
                      ],
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
                      Text(
                        'Описание',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _book!['description'] ?? 'Описание отсутствует',
                        style: TextStyle(
                          color: palette.text.withValues(alpha: 0.76),
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildCommunityChaptersHeader(),
                    ],
                  ),
                ),
              ),

              // Detail section
              if (_selectedDetailSection == 'chapters')
                _chapters.isNotEmpty
                    ? SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
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
                                  ? palette.accentGradient
                                  : LinearGradient(
                                      colors: [
                                        palette.elevated.withValues(
                                          alpha: palette.isDark ? 0.42 : 0.90,
                                        ),
                                        palette.surface.withValues(
                                          alpha: palette.isDark ? 0.22 : 0.58,
                                        ),
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isCurrent
                                    ? Colors.transparent
                                    : palette.border,
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
                                      ? palette.onAccent.withValues(alpha: 0.18)
                                      : palette.accent.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    '$chapterNum',
                                    style: TextStyle(
                                      color: isCurrent
                                          ? palette.onAccent
                                          : palette.accent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                chapter['title'] ?? 'Глава $chapterNum',
                                style: TextStyle(
                                  color: isCurrent
                                      ? palette.onAccent
                                      : palette.text.withValues(alpha: 0.84),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: Icon(
                                isCurrent
                                    ? Icons.play_circle_filled_rounded
                                    : Icons.arrow_forward_ios_rounded,
                                color: isCurrent
                                    ? palette.onAccent
                                    : palette.mutedText.withValues(alpha: 0.60),
                                size: isCurrent ? 24 : 16,
                              ),
                              onTap: () => _openReader(chapterNum),
                            ),
                          );
                        }, childCount: _chapters.length),
                      )
                    : SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 40,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: palette.elevated.withValues(
                                alpha: palette.isDark ? 0.42 : 0.92,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: palette.border,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: palette.accent.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.menu_book_outlined,
                                    size: 60,
                                    color: palette.accent,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Главы отсутствуют',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: palette.text,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Эта книга пока не содержит глав для чтения',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: palette.mutedText,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

              if (_selectedDetailSection == 'reviews')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    child: BookReviewsSection(
                      token: widget.token,
                      bookId: widget.bookId,
                      initialRating: _userRating,
                      onRatingChanged: (rating) =>
                          setState(() => _userRating = rating),
                    ),
                  ),
                ),

              if (_selectedDetailSection == 'quotes')
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 6,
                    ),
                    child: BookQuotesSection(
                      token: widget.token,
                      bookId: widget.bookId,
                    ),
                  ),
                ),

              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 40,
                ),
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
            if (item is Map && item.containsKey('name')) {
              return item['name']?.toString() ?? '';
            }
            return item.toString();
          })
          .where((value) => value.isNotEmpty)
          .toList();
    }
    return [raw.toString()];
  }

  String _bookLanguage() {
    final raw =
        _book!['language'] ?? _book!['languageCode'] ?? _book!['language_code'];
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
      case 'kk':
      case 'kaz':
      case 'kazakh':
      case 'қазақша':
        return 'Қазақша';
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
            .map(
              (word) => word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1)}',
            )
            .join(' ');
    }
  }

  int _bookPages() {
    final raw =
        _book!['page_count'] ?? _book!['pageCount'] ?? _book!['num_pages'];
    if (raw == null) return 0;
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? 0;
  }

  Widget _buildMoreLikeThisSection() {
    final palette = context.palette;
    if (_isSimilarLoading && _similarBooks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: _softPanelDecoration(),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Подбираем похожие книги',
              style: TextStyle(color: palette.text),
            ),
          ],
        ),
      );
    }
    if (_similarBooks.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _softPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: palette.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Похожие книги',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 178,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _similarBooks.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(
                  _similarBooks[index] as Map,
                );
                final book = Map<String, dynamic>.from(item['book'] as Map);
                return _buildSimilarCard(book, item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarCard(
    Map<String, dynamic> book,
    Map<String, dynamic> item,
  ) {
    final palette = context.palette;
    final id = _asInt(book['id']);
    final cover = book['coverUrl']?.toString() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(token: widget.token, bookId: id),
        ),
      ),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: cover.isEmpty
                  ? Container(
                      width: 112,
                      height: 112,
                      color: palette.surface,
                      child: Icon(
                        Icons.menu_book_rounded,
                        color: palette.mutedText,
                      ),
                    )
                  : Image.network(
                      ApiConstants.getCoverUrl(cover),
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 112,
                        height: 112,
                        color: palette.surface,
                        child: Icon(
                          Icons.menu_book_rounded,
                          color: palette.mutedText,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              book['title']?.toString() ?? 'Без названия',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item['reason']?.toString() ?? 'AI match',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.accent, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  BoxDecoration _softPanelDecoration() {
    final palette = context.palette;
    return BoxDecoration(
      color: palette.elevated.withValues(alpha: palette.isDark ? 0.62 : 0.88),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: palette.border, width: 1.3),
    );
  }

  Widget _buildCommunityChaptersHeader() {
    final palette = context.palette;
    return Row(
      children: [
        _buildCommunityTabButton(
          icon: Icons.rate_review_rounded,
          label: 'Отзывы',
          selected: _selectedDetailSection == 'reviews',
          onTap: () => _selectDetailSection('reviews'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _selectDetailSection('chapters'),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: _selectedDetailSection == 'chapters'
                    ? palette.accentGradient
                    : LinearGradient(
                        colors: [
                          palette.accent.withValues(alpha: 0.20),
                          palette.secondaryAccent.withValues(alpha: 0.10),
                        ],
                      ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _selectedDetailSection == 'chapters'
                      ? Colors.transparent
                      : palette.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    color: _selectedDetailSection == 'chapters'
                        ? palette.onAccent
                        : palette.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Главы',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _selectedDetailSection == 'chapters'
                            ? palette.onAccent
                            : palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_chapters.length}',
                    style: TextStyle(
                      color: _selectedDetailSection == 'chapters'
                          ? palette.onAccent
                          : palette.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _buildCommunityTabButton(
          icon: Icons.format_quote_rounded,
          label: 'Цитаты',
          selected: _selectedDetailSection == 'quotes',
          onTap: () => _selectDetailSection('quotes'),
        ),
      ],
    );
  }

  Widget _buildCommunityTabButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return SizedBox(
      width: 68,
      height: 52,
      child: selected
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _buildCommunityTabLabel(
                icon: icon,
                label: label,
                iconColor: palette.onAccent,
                textColor: palette.onAccent,
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                side: BorderSide(color: palette.border),
                foregroundColor: palette.mutedText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _buildCommunityTabLabel(
                icon: icon,
                label: label,
                iconColor: palette.accent,
                textColor: palette.mutedText,
              ),
            ),
    );
  }

  Widget _buildCommunityTabLabel({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color textColor,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildUserRatingPanel() {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _softPanelDecoration(),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.accent.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.star_rounded, color: palette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ваша оценка',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _userRating == 0
                      ? '0: прочитано без оценки'
                      : '$_userRating из 5',
                  style: TextStyle(color: palette.mutedText, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_isRatingSaving)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var rating = 1; rating <= 5; rating++)
                  InkResponse(
                    radius: 20,
                    onTap: () => _saveRating(rating),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        rating <= _userRating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: palette.warning,
                        size: 26,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMarkAsReadButton() {
    final palette = context.palette;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: _isMarkReadSaving ? null : _markAsRead,
        icon: _isMarkReadSaving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.onAccent,
                ),
              )
            : const Icon(Icons.done_all_rounded),
        label: const Text('Отметить как прочитанное'),
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final palette = context.palette;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: enabled
            ? palette.accentGradient
            : LinearGradient(
                colors: [
                  palette.text.withValues(alpha: 0.05),
                  palette.text.withValues(alpha: 0.03),
                ],
              ),
        borderRadius: BorderRadius.circular(16),
        border: enabled ? null : Border.all(color: palette.border, width: 1.5),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.28),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: palette.onAccent,
          disabledForegroundColor: palette.mutedText.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: palette.isDark ? 0.38 : 0.74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.text.withValues(alpha: 0.84),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildLanguageChip(String language) {
    final palette = context.palette;
    final flag = _languageFlag(_bookLanguageCode());
    final display = 'Язык: $language';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: palette.isDark ? 0.38 : 0.74),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
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
                color: palette.surface.withValues(alpha: 0.70),
              ),
              alignment: Alignment.center,
              child: Text(flag, style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            display,
            style: TextStyle(
              color: palette.text.withValues(alpha: 0.84),
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
    final raw =
        _book!['language'] ?? _book!['languageCode'] ?? _book!['language_code'];
    if (raw == null) return '';
    return raw.toString().trim().toLowerCase();
  }

  Widget _buildPlaceholder() {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.text.withValues(alpha: palette.isDark ? 0.05 : 0.14),
            palette.text.withValues(alpha: palette.isDark ? 0.02 : 0.06),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.book_rounded,
          size: 80,
          color: palette.mutedText.withValues(alpha: 0.70),
        ),
      ),
    );
  }
}
