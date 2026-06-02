import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ebookreader/models/book_annotation.dart';
import 'package:ebookreader/models/community_review.dart';
import 'package:ebookreader/models/favorite_quote.dart';
import 'package:ebookreader/models/lookup_result.dart';
import 'package:ebookreader/screens/audio/audio_player_screen.dart';
import 'package:ebookreader/services/annotation_service.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:ebookreader/services/community_service.dart';
import 'package:ebookreader/services/lookup_service.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Экран чтения книги.
///
/// Отображает содержимое главы с настраиваемым размером шрифта и яркостью.
/// Поддерживает навигацию между главами, скрытие/показ панели управления
/// по нажатию на экран, а также автоматическое сохранение прогресса чтения.
class ReaderScreen extends StatefulWidget {
  final String token;
  final int bookId;
  final int chapterOrder;
  final double initialSegmentProgress;
  final int initialRating;

  const ReaderScreen({
    super.key,
    required this.token,
    required this.bookId,
    required this.chapterOrder,
    this.initialSegmentProgress = 0.0,
    this.initialRating = 0,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();
  final AnnotationService _annotationService = AnnotationService();
  final CommunityService _communityService = CommunityService();
  final LookupService _lookupService = LookupService();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _chapter;
  String _bookTitle = '';
  String _bookAuthor = '';
  String _bookCoverUrl = '';
  String _bookAvailability = 'TEXT';
  List<BookAnnotation> _annotations = [];
  int _currentChapter = 1;
  int _totalChapters = 0;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isRatingSaving = false;
  bool _isLookupLoading = false;
  int _userRating = 0;
  TextSelection? _selection;
  String _selectedText = '';
  double _fontSize = 18;
  double _brightness = 1.0;
  double _horizontalPadding = 24;
  double _verticalPadding = 24;
  Color? _customReaderBackgroundColor;
  Color? _customReaderFontColor;
  Color? _customReaderHighlightColor;
  Color? _customReaderTranslationColor;
  double _segmentProgress = 0.0;
  BookAnnotation? _pendingScrollAnnotation;
  Timer? _progressSaveTimer;
  bool _restoredInitialScroll = false;
  late AnimationController _animController;
  static const int _maxQuoteWords = 120;
  static const String _systemFontFamily = 'System';
  static const String _readerFontPreferenceKey = 'reader_font_family';
  static const String _readerHorizontalPaddingKey = 'reader_horizontal_padding';
  static const String _readerVerticalPaddingKey = 'reader_vertical_padding';
  static const String _readerBackgroundColorKey = 'reader_background_color';
  static const String _readerFontColorKey = 'reader_font_color';
  static const String _readerHighlightColorKey = 'reader_highlight_color';
  static const String _readerTranslationColorKey = 'reader_translation_color';
  static const String _readerRecentColorsKey = 'reader_recent_colors';
  String _readerFontFamily = _systemFontFamily;
  List<Color> _recentReaderColors = [];

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapterOrder;
    _segmentProgress = widget.initialSegmentProgress.clamp(0.0, 1.0).toDouble();
    _userRating = widget.initialRating.clamp(0, 5);
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..value = 1.0;
    _scrollController.addListener(_onScrollProgressChanged);
    _loadReaderPreferences();
    _loadChapter();
  }

  @override
  void dispose() {
    _progressSaveTimer?.cancel();
    _saveTextProgress();
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChapter() async {
    setState(() => _isLoading = true);
    try {
      final chapter = await _bookService.getChapter(
        widget.token,
        widget.bookId,
        _currentChapter,
      );
      final book = await _bookService.getBookById(widget.token, widget.bookId);
      final chapters = await _bookService.getBookChapters(
        widget.token,
        widget.bookId,
      );
      final annotations = await _loadChapterAnnotationsSafely();
      final progress = await _loadProgressSafely();

      await _saveTextProgress();

      if (!mounted) return;
      setState(() {
        _chapter = chapter;
        _bookTitle = book['title']?.toString() ?? '';
        _bookAuthor = book['author']?.toString() ?? '';
        _bookCoverUrl = book['coverUrl']?.toString() ?? '';
        _bookAvailability = book['availability']?.toString() ?? 'METADATA_ONLY';
        _annotations = annotations;
        _userRating = _asRating(progress['rating']);
        _selection = null;
        _selectedText = '';
        _totalChapters = chapters.length;
        _isLoading = false;
      });

      // ✅ ИСПРАВЛЕНО: Прокручиваем только после отрисовки виджета
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          final maxScroll = _scrollController.position.maxScrollExtent;
          final pending = _pendingScrollAnnotation;
          final content = _chapter?['content']?.toString() ?? '';
          if (pending != null && content.isNotEmpty) {
            final target = (pending.startOffset / content.length).clamp(
              0.0,
              1.0,
            );
            _scrollController.jumpTo(
              (maxScroll * target - 120).clamp(0.0, maxScroll),
            );
            _pendingScrollAnnotation = null;
          } else {
            final shouldRestore =
                !_restoredInitialScroll && _segmentProgress > 0;
            _scrollController.jumpTo(
              shouldRestore ? maxScroll * _segmentProgress : 0,
            );
          }
          _restoredInitialScroll = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
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

  Future<List<BookAnnotation>> _loadChapterAnnotationsSafely() async {
    try {
      return await _annotationService.getChapterAnnotations(
        widget.token,
        widget.bookId,
        _currentChapter,
      );
    } catch (e) {
      debugPrint('Reader annotations unavailable: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> _loadProgressSafely() async {
    try {
      final progress = await _bookmarkService.getProgress(
        widget.token,
        widget.bookId,
      );
      return Map<String, dynamic>.from(progress);
    } catch (e) {
      debugPrint('Reader progress unavailable: $e');
      return const {};
    }
  }

  Future<void> _loadReaderPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedFont = prefs.getString(_readerFontPreferenceKey);
    final savedHorizontalPadding = prefs.getDouble(_readerHorizontalPaddingKey);
    final savedVerticalPadding = prefs.getDouble(_readerVerticalPaddingKey);
    final savedBackgroundColor = prefs.getInt(_readerBackgroundColorKey);
    final savedFontColor = prefs.getInt(_readerFontColorKey);
    final savedHighlightColor = prefs.getInt(_readerHighlightColorKey);
    final savedTranslationColor = prefs.getInt(_readerTranslationColorKey);
    final savedRecentColors = prefs.getStringList(_readerRecentColorsKey);
    if (!mounted) return;
    setState(() {
      if (savedFont != null &&
          _readerFontOptions.any((font) => font.family == savedFont)) {
        _readerFontFamily = savedFont;
      }
      if (savedHorizontalPadding != null) {
        _horizontalPadding = savedHorizontalPadding.clamp(12.0, 56.0);
      }
      if (savedVerticalPadding != null) {
        _verticalPadding = savedVerticalPadding.clamp(12.0, 64.0);
      }
      if (savedBackgroundColor != null) {
        _customReaderBackgroundColor = Color(savedBackgroundColor);
      }
      if (savedFontColor != null) {
        _customReaderFontColor = Color(savedFontColor);
      }
      if (savedHighlightColor != null) {
        _customReaderHighlightColor = Color(savedHighlightColor);
      }
      if (savedTranslationColor != null) {
        _customReaderTranslationColor = Color(savedTranslationColor);
      }
      if (savedRecentColors != null) {
        _recentReaderColors = savedRecentColors
            .map(int.tryParse)
            .whereType<int>()
            .map(Color.new)
            .toList();
      }
    });
  }

  void _nextChapter() {
    if (_currentChapter < _totalChapters) {
      setState(() {
        _currentChapter++;
        _segmentProgress = 0.0;
        _selection = null;
        _selectedText = '';
        _restoredInitialScroll = true;
      });
      _loadChapter();
    }
  }

  void _prevChapter() {
    if (_currentChapter > 1) {
      setState(() {
        _currentChapter--;
        _segmentProgress = 0.0;
        _selection = null;
        _selectedText = '';
        _restoredInitialScroll = true;
      });
      _loadChapter();
    }
  }

  void _onSelectionChanged(
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final content = _chapter?['content']?.toString() ?? '';
    final start = selection.start;
    final end = selection.end;
    if (selection.isCollapsed ||
        start < 0 ||
        end <= start ||
        end > content.length) {
      setState(() {
        _selection = null;
        _selectedText = '';
      });
      return;
    }

    setState(() {
      _selection = selection;
      _selectedText = content.substring(start, end).trim();
    });
  }

  Future<void> _createHighlight() async {
    final selection = _selection;
    final content = _chapter?['content']?.toString() ?? '';
    if (selection == null ||
        _selectedText.isEmpty ||
        selection.end > content.length) {
      return;
    }

    try {
      final annotation = await _annotationService.createAnnotation(
        token: widget.token,
        bookId: widget.bookId,
        chapterOrder: _currentChapter,
        startOffset: selection.start,
        endOffset: selection.end,
        highlightedText: content.substring(selection.start, selection.end),
        color: _colorToHex(_readerHighlightColor),
      );
      setState(() {
        _annotations = [..._annotations, annotation]
          ..sort((a, b) => a.startOffset.compareTo(b.startOffset));
        _selection = null;
        _selectedText = '';
      });
      if (mounted) {
        await _showNoteEditor(annotation);
      }
    } catch (e) {
      _showError('Ошибка сохранения выделения: $e');
    }
  }

  Future<void> _publishSelectedQuote() async {
    final selection = _selection;
    final content = _chapter?['content']?.toString() ?? '';
    if (selection == null ||
        _selectedText.isEmpty ||
        selection.end > content.length) {
      return;
    }
    if (_wordCount(_selectedText) > _maxQuoteWords) {
      _showError('Цитата не может быть длиннее $_maxQuoteWords слов');
      return;
    }

    try {
      final annotation = await _annotationService.createAnnotation(
        token: widget.token,
        bookId: widget.bookId,
        chapterOrder: _currentChapter,
        startOffset: selection.start,
        endOffset: selection.end,
        highlightedText: content.substring(selection.start, selection.end),
        color: _colorToHex(_readerTranslationColor),
      );
      await _communityService.publishQuote(
        token: widget.token,
        bookId: widget.bookId,
        annotationId: annotation.id,
      );
      if (!mounted) return;
      setState(() {
        _annotations = [..._annotations, annotation]
          ..sort((a, b) => a.startOffset.compareTo(b.startOffset));
        _selection = null;
        _selectedText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Цитата опубликована'),
          backgroundColor: context.palette.success,
        ),
      );
    } catch (e) {
      _showError('Ошибка публикации цитаты: $e');
    }
  }

  int _wordCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  Future<void> _openLookupSheet() async {
    final selection = _selection;
    final selectedText = _selectedText;
    if (selection == null || selectedText.trim().isEmpty) return;

    setState(() => _isLookupLoading = true);
    LookupResult result;
    try {
      result = await _lookupService.lookupSelection(
        token: widget.token,
        text: selectedText,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLookupLoading = false);
      _showError('Ошибка словаря: $e');
      return;
    }

    if (!mounted) return;
    setState(() => _isLookupLoading = false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LookupSheet(
        result: result,
        selectedText: selectedText,
        onSave: () => _saveLookupAnnotation(result, selection, selectedText),
      ),
    );
  }

  Future<void> _saveLookupAnnotation(
    LookupResult result,
    TextSelection selection,
    String selectedText,
  ) async {
    final content = _chapter?['content']?.toString() ?? '';
    if (selection.end > content.length || selection.start < 0) {
      _showError('Выделение больше не совпадает с текстом главы');
      return;
    }

    try {
      final annotation = await _annotationService.createAnnotation(
        token: widget.token,
        bookId: widget.bookId,
        chapterOrder: _currentChapter,
        startOffset: selection.start,
        endOffset: selection.end,
        highlightedText: content.substring(selection.start, selection.end),
        note: _buildLookupNote(result),
        color: _colorToHex(_readerTranslationColor),
      );
      if (!mounted) return;
      setState(() {
        _annotations = [..._annotations, annotation]
          ..sort((a, b) => a.startOffset.compareTo(b.startOffset));
        _selection = null;
        _selectedText = '';
      });
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Сохранено в словарь'),
          backgroundColor: context.palette.success,
        ),
      );
    } catch (e) {
      _showError('Ошибка сохранения в словарь: $e');
    }
  }

  String _buildLookupNote(LookupResult result) {
    String? definition;
    for (final item in result.definitions) {
      final candidate = item.definition.trim();
      if (candidate.isNotEmpty) {
        definition = candidate;
        break;
      }
    }
    final translation = result.translation?.text.trim();
    final sources = <String>{
      ...result.definitions
          .map((item) => item.source)
          .where((item) => item.trim().isNotEmpty),
      if (result.translation?.source.trim().isNotEmpty == true)
        result.translation!.source,
    };

    final lines = <String>['Словарь'];
    if (definition != null && definition.isNotEmpty) {
      lines.add('Определение: $definition');
    }
    if (translation != null && translation.isNotEmpty) {
      lines.add('Перевод: $translation');
    }
    if (sources.isNotEmpty) {
      lines.add('Источник: ${sources.join(' / ')}');
    }
    return lines.join('\n');
  }

  Color _displayAnnotationColor(BookAnnotation annotation) {
    if (_isTranslationAnnotation(annotation)) {
      return _readerTranslationColor;
    }
    return _readerHighlightColor;
  }

  bool _isTranslationAnnotation(BookAnnotation annotation) {
    return annotation.note.contains('Перевод:');
  }

  Color get _readerBackgroundColor =>
      _customReaderBackgroundColor ?? context.palette.background;

  Color get _readerFontColor => _customReaderFontColor ?? context.palette.text;

  Color get _readerHighlightColor =>
      _customReaderHighlightColor ?? context.palette.highlight;

  Color get _readerTranslationColor =>
      _customReaderTranslationColor ?? const Color(0xFFFFD166);

  String _colorToHex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Future<void> _showNoteEditor(BookAnnotation annotation) async {
    final updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AnnotationNoteSheet(annotation: annotation),
    );

    if (updated == null || !mounted) return;
    await _updateAnnotationNote(annotation, updated);
  }

  Future<void> _updateAnnotationNote(
    BookAnnotation annotation,
    String note,
  ) async {
    try {
      final updated = await _annotationService.updateAnnotation(
        token: widget.token,
        bookId: widget.bookId,
        annotationId: annotation.id,
        note: note,
        color: annotation.color,
      );
      if (!mounted) return;
      setState(() {
        _annotations = _annotations
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    } catch (e) {
      _showError('Ошибка обновления заметки: $e');
    }
  }

  Future<void> _deleteAnnotation(BookAnnotation annotation) async {
    try {
      await _annotationService.deleteAnnotation(
        widget.token,
        widget.bookId,
        annotation.id,
      );
      setState(() {
        _annotations = _annotations
            .where((item) => item.id != annotation.id)
            .toList();
      });
    } catch (e) {
      _showError('Ошибка удаления заметки: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openAnnotationsSheet() async {
    List<BookAnnotation> allAnnotations;
    try {
      allAnnotations = await _annotationService.getBookAnnotations(
        widget.token,
        widget.bookId,
      );
    } catch (e) {
      _showError('Ошибка загрузки заметок: $e');
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final palette = context.palette;
          return Container(
            height: MediaQuery.of(context).size.height * 0.72,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Выделения и заметки',
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${allAnnotations.length}',
                          style: TextStyle(
                            color: palette.accent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: allAnnotations.isEmpty
                        ? Center(
                            child: Text(
                              'Выделите текст в книге, и он появится здесь.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: palette.mutedText,
                                height: 1.45,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: allAnnotations.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final annotation = allAnnotations[index];
                              return _buildAnnotationCard(
                                annotation,
                                onTap: () {
                                  Navigator.pop(context);
                                  _jumpToAnnotation(annotation);
                                },
                                onEdit: () async {
                                  await _showNoteEditor(annotation);
                                  allAnnotations = await _annotationService
                                      .getBookAnnotations(
                                        widget.token,
                                        widget.bookId,
                                      );
                                  setModalState(() {});
                                },
                                onDelete: () async {
                                  await _deleteAnnotation(annotation);
                                  allAnnotations = allAnnotations
                                      .where((item) => item.id != annotation.id)
                                      .toList();
                                  setModalState(() {});
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _jumpToAnnotation(BookAnnotation annotation) {
    _pendingScrollAnnotation = annotation;
    if (annotation.chapterOrder == _currentChapter) {
      final content = _chapter?['content']?.toString() ?? '';
      if (_scrollController.hasClients && content.isNotEmpty) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final target = (annotation.startOffset / content.length).clamp(
          0.0,
          1.0,
        );
        _scrollController.animateTo(
          (maxScroll * target - 120).clamp(0.0, maxScroll),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    setState(() {
      _currentChapter = annotation.chapterOrder;
      _segmentProgress = 0.0;
      _restoredInitialScroll = true;
    });
    _loadChapter();
  }

  void _onScrollProgressChanged() {
    if (!_scrollController.hasClients || _isLoading) return;
    final direction = _scrollController.position.userScrollDirection;
    if (_showControls &&
        direction != ScrollDirection.idle &&
        _scrollController.offset > 8) {
      setState(() => _showControls = false);
      _animController.reverse();
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      _segmentProgress = 0.0;
    } else {
      _segmentProgress = (_scrollController.offset / maxScroll)
          .clamp(0.0, 1.0)
          .toDouble();
    }
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(seconds: 2), _saveTextProgress);
  }

  Future<void> _saveTextProgress() async {
    try {
      await _bookmarkService.updateProgress(
        widget.token,
        widget.bookId,
        _currentChapter,
        segmentProgress: _segmentProgress,
        lastMode: 'TEXT',
      );
    } catch (e) {
      debugPrint('Ошибка сохранения прогресса чтения: $e');
    }
  }

  bool get _bookHasAudio =>
      _bookAvailability == 'AUDIO' || _bookAvailability == 'SYNCED';

  Future<void> _openAudioFromReader() async {
    await _saveTextProgress();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AudioPlayerScreen(
          token: widget.token,
          bookId: widget.bookId,
          title: _bookTitle.isEmpty ? 'Книга #${widget.bookId}' : _bookTitle,
          author: _bookAuthor,
          coverUrl: _bookCoverUrl,
          initialSegmentOrder: _currentChapter,
          initialSegmentProgress: _segmentProgress,
          initialLastMode: 'TEXT',
        ),
      ),
    );
  }

  int _asRating(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value.clamp(0, 5);
    if (value is num) return value.toInt().clamp(0, 5);
    return (int.tryParse(value.toString()) ?? 0).clamp(0, 5);
  }

  Future<void> _saveRating(int rating, StateSetter? setModalState) async {
    if (_isRatingSaving || rating < 1 || rating > 5) return;
    final previous = _userRating;
    final nextRating = previous == rating ? 0 : rating;
    setState(() {
      _userRating = nextRating;
      _isRatingSaving = true;
    });
    setModalState?.call(() {});

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
      setModalState?.call(() {});
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
      setModalState?.call(() {});
      _showError('Ошибка сохранения оценки: $e');
    }
  }

  void _showRatingSheet() {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentPalette = context.palette;
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            decoration: BoxDecoration(
              color: currentPalette.elevated,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: currentPalette.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: palette.isDark ? 0.35 : 0.12,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, -10),
                ),
              ],
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
                        color: currentPalette.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Оценить книгу',
                    style: TextStyle(
                      color: currentPalette.text,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _bookTitle.isEmpty ? 'Книга #${widget.bookId}' : _bookTitle,
                    style: TextStyle(color: currentPalette.mutedText),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: _isRatingSaving
                        ? CircularProgressIndicator(
                            color: currentPalette.accent,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var rating = 1; rating <= 5; rating++)
                                IconButton(
                                  tooltip: '$rating из 5',
                                  onPressed: () =>
                                      _saveRating(rating, setModalState),
                                  iconSize: 42,
                                  icon: Icon(
                                    rating <= _userRating
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    color: currentPalette.warning,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      _userRating == 0
                          ? '0: прочитано без оценки'
                          : 'Ваша оценка: $_userRating из 5',
                      style: TextStyle(color: currentPalette.mutedText),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: _showControls
          ? AppBar(
              backgroundColor: palette.surface,
              elevation: 0,
              title: Text(
                _chapter?['title'] ?? 'Глава $_currentChapter',
                style: TextStyle(fontSize: 16, color: palette.text),
              ),
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: palette.text),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (_bookHasAudio)
                  IconButton(
                    icon: Icon(Icons.headphones_rounded, color: palette.accent),
                    tooltip: 'Слушать',
                    onPressed: _openAudioFromReader,
                  ),
                IconButton(
                  icon: Icon(
                    _userRating > 0
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: _userRating > 0 ? palette.warning : palette.accent,
                  ),
                  tooltip: 'Оценка',
                  onPressed: _showRatingSheet,
                ),
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.border_color_rounded, color: palette.accent),
                      if (_annotations.isNotEmpty)
                        Positioned(
                          right: -3,
                          top: -4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  tooltip: 'Выделения',
                  onPressed: _openAnnotationsSheet,
                ),
                IconButton(
                  icon: Icon(Icons.settings, color: palette.accent),
                  onPressed: _showFontSettings,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: palette.accent,
                strokeWidth: 2.5,
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Container(
                decoration: BoxDecoration(
                  color: _customReaderBackgroundColor == null
                      ? null
                      : _readerBackgroundColor,
                  gradient: _customReaderBackgroundColor == null
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [palette.background, palette.surface],
                        )
                      : null,
                ),
                child: Opacity(
                  opacity: _brightness,
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          _horizontalPadding,
                          _showControls
                              ? _verticalPadding
                              : _verticalPadding + 56,
                          _horizontalPadding,
                          _verticalPadding + 96,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Chapter title
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    palette.elevated.withValues(
                                      alpha: palette.isDark ? 0.48 : 0.92,
                                    ),
                                    palette.surface.withValues(
                                      alpha: palette.isDark ? 0.26 : 0.70,
                                    ),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: palette.border,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Глава $_currentChapter',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: palette.accent,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _chapter?['title'] ?? 'Без названия',
                                    style: _readerTextStyle(
                                      TextStyle(
                                        fontSize: _fontSize + 6,
                                        fontWeight: FontWeight.bold,
                                        color: _readerFontColor,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Content
                            SelectableText.rich(
                              _buildHighlightedContent(),
                              onSelectionChanged: _onSelectionChanged,
                            ),
                          ],
                        ),
                      ),

                      if (_selection != null && _selectedText.isNotEmpty)
                        Positioned(
                          right: 20,
                          bottom: _showControls ? 116 : 28,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.elevated,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: palette.border),
                              boxShadow: [
                                BoxShadow(
                                  color: palette.accent.withValues(alpha: 0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton.icon(
                                    onPressed: _createHighlight,
                                    icon: Icon(
                                      Icons.edit_note_rounded,
                                      color: palette.accent,
                                    ),
                                    label: Text(
                                      'Выделить',
                                      style: TextStyle(
                                        color: palette.text,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 28,
                                    color: palette.border,
                                  ),
                                  TextButton.icon(
                                    onPressed:
                                        _wordCount(_selectedText) <=
                                            _maxQuoteWords
                                        ? _publishSelectedQuote
                                        : null,
                                    icon: Icon(
                                      Icons.format_quote_rounded,
                                      color:
                                          _wordCount(_selectedText) <=
                                              _maxQuoteWords
                                          ? palette.accent
                                          : palette.mutedText,
                                    ),
                                    label: Text(
                                      'Цитата',
                                      style: TextStyle(
                                        color:
                                            _wordCount(_selectedText) <=
                                                _maxQuoteWords
                                            ? palette.text
                                            : palette.mutedText,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 28,
                                    color: palette.border,
                                  ),
                                  TextButton.icon(
                                    onPressed: _isLookupLoading
                                        ? null
                                        : _openLookupSheet,
                                    icon: _isLookupLoading
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: palette.accent,
                                            ),
                                          )
                                        : Icon(
                                            Icons.menu_book_rounded,
                                            color: palette.accent,
                                          ),
                                    label: Text(
                                      'Словарь',
                                      style: TextStyle(
                                        color: _isLookupLoading
                                            ? palette.mutedText
                                            : palette.text,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Navigation bottom bar
                      if (_showControls)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedBuilder(
                            animation: _animController,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(
                                  0,
                                  100 * (1 - _animController.value),
                                ),
                                child: child,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    palette.elevated.withValues(
                                      alpha: palette.isDark ? 0.95 : 0.98,
                                    ),
                                    palette.background,
                                  ],
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: palette.border,
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: SafeArea(
                                top: false,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: _buildChapterNavButton(
                                        icon: Icons.arrow_back_rounded,
                                        label: 'Назад',
                                        enabled: _currentChapter > 1,
                                        accent: false,
                                        onPressed: _prevChapter,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: palette.accentGradient,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '$_currentChapter/$_totalChapters',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: palette.onAccent,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildChapterNavButton(
                                        icon: Icons.arrow_forward_rounded,
                                        label: 'Вперёд',
                                        enabled:
                                            _currentChapter < _totalChapters,
                                        accent: true,
                                        onPressed: _nextChapter,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  TextSpan _buildHighlightedContent() {
    final content = _chapter?['content']?.toString() ?? '';
    final baseStyle = _readerTextStyle(
      TextStyle(
        fontSize: _fontSize,
        height: 1.9,
        color: _readerFontColor.withValues(alpha: 0.88),
        letterSpacing: 0.3,
      ),
    );
    if (content.isEmpty || _annotations.isEmpty) {
      return TextSpan(text: content, style: baseStyle);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    final sorted = [..._annotations]
      ..sort((a, b) => a.startOffset.compareTo(b.startOffset));

    for (final annotation in sorted) {
      final start = annotation.startOffset.clamp(0, content.length);
      final end = annotation.endOffset.clamp(0, content.length);
      if (end <= start || start < cursor) continue;
      final annotationColor = _displayAnnotationColor(annotation);

      if (start > cursor) {
        spans.add(
          TextSpan(text: content.substring(cursor, start), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: content.substring(start, end),
          style: baseStyle.copyWith(
            color: _readerFontColor,
            backgroundColor: annotationColor.withValues(alpha: 0.38),
            decoration: TextDecoration.underline,
            decorationColor: annotationColor.withValues(alpha: 0.85),
            decorationThickness: 1.2,
          ),
        ),
      );
      cursor = end;
    }

    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor), style: baseStyle));
    }
    return TextSpan(children: spans, style: baseStyle);
  }

  Widget _buildChapterNavButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required bool accent,
    required VoidCallback onPressed,
  }) {
    final palette = context.palette;
    return Container(
      height: 54,
      decoration: BoxDecoration(
        gradient: enabled && accent ? palette.accentGradient : null,
        color: !enabled || !accent
            ? palette.text.withValues(alpha: palette.isDark ? 0.05 : 0.08)
            : null,
        borderRadius: BorderRadius.circular(12),
        border: !enabled || !accent ? Border.all(color: palette.border) : null,
      ),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: enabled
              ? (accent ? palette.onAccent : palette.text)
              : palette.mutedText.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnotationCard(
    BookAnnotation annotation, {
    required VoidCallback onTap,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final palette = context.palette;
    final annotationColor = _displayAnnotationColor(annotation);
    return Material(
      color: palette.elevated.withValues(alpha: palette.isDark ? 0.55 : 0.90),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: annotationColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Глава ${annotation.chapterOrder}',
                      style: TextStyle(
                        color: annotationColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit_rounded,
                      color: palette.mutedText,
                      size: 20,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red.shade200,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                annotation.highlightedText,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _readerFontColor.withValues(alpha: 0.86),
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (annotation.note.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  annotation.note,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.mutedText, height: 1.35),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showFontSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final palette = context.palette;
          final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [palette.elevated, palette.background],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: palette.border, width: 1.5),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: palette.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Настройки чтения',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const AppThemePicker(),
                      const SizedBox(height: 28),
                      _buildReaderFontRow(),
                      const SizedBox(height: 14),
                      _buildReaderAdditionalSettingsRow(),
                      const SizedBox(height: 24),
                      _buildReaderSliderRow(
                        icon: Icons.format_size,
                        label: 'Размер шрифта',
                        value: _fontSize,
                        min: 14,
                        max: 28,
                        divisions: 7,
                        trailing: '${_fontSize.round()}',
                        onChanged: (value) {
                          setState(() => _fontSize = value);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildReaderSliderRow(
                        icon: Icons.brightness_6,
                        label: 'Яркость',
                        value: _brightness,
                        min: 0.5,
                        max: 1.0,
                        onChanged: (value) {
                          setState(() => _brightness = value);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: 18),
                      _buildResetReaderSettingsButton(
                        () => setModalState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderFontRow() {
    final palette = context.palette;
    final selectedFont = _readerFontOptions.firstWhere(
      (font) => font.family == _readerFontFamily,
      orElse: () => _readerFontOptions.first,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _openFontSelector,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.elevated.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.accent.withValues(alpha: 0.2),
                    palette.secondaryAccent.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.font_download_rounded, color: palette.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Шрифт',
                    style: TextStyle(
                      color: palette.text.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedFont.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _fontPreviewStyle(
                      selectedFont.family,
                      TextStyle(
                        color: palette.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded, color: palette.mutedText),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderAdditionalSettingsRow() {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _openAdditionalSettings,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.elevated.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    palette.accent.withValues(alpha: 0.2),
                    palette.secondaryAccent.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.tune_rounded, color: palette.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Дополнительно',
                    style: TextStyle(
                      color: palette.text.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Отступы и цвета',
                    style: TextStyle(
                      color: palette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded, color: palette.mutedText),
          ],
        ),
      ),
    );
  }

  Widget _buildResetReaderSettingsButton(VoidCallback refreshSheet) {
    final palette = context.palette;
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        onPressed: () => _confirmResetReaderSettings(refreshSheet),
        icon: Icon(Icons.restart_alt_rounded, size: 17, color: palette.danger),
        label: Text(
          'Вернуть настройки чтения по умолчанию',
          style: TextStyle(
            color: palette.danger,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  Widget _buildReaderSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    int? divisions,
    String? trailing,
  }) {
    final palette = context.palette;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                palette.accent.withValues(alpha: 0.2),
                palette.secondaryAccent.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: palette.accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: palette.text.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: palette.accent,
                inactiveColor: palette.border,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Future<void> _openFontSelector() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ReaderFontPickerScreen(
          selectedFamily: _readerFontFamily,
          fonts: _readerFontOptions,
        ),
      ),
    );
    if (!mounted || selected == null || selected == _readerFontFamily) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readerFontPreferenceKey, selected);
    if (!mounted) return;
    setState(() => _readerFontFamily = selected);
  }

  Future<void> _openAdditionalSettings() async {
    final selected = await Navigator.of(context)
        .push<_ReaderAdditionalSettings>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _ReaderAdditionalSettingsScreen(
              horizontalPadding: _horizontalPadding,
              verticalPadding: _verticalPadding,
              backgroundColor: _readerBackgroundColor,
              fontColor: _readerFontColor,
              highlightColor: _readerHighlightColor,
              translationColor: _readerTranslationColor,
              defaultBackgroundColor: context.palette.background,
              defaultFontColor: context.palette.text,
              defaultHighlightColor: context.palette.highlight,
              defaultTranslationColor: const Color(0xFFFFD166),
              recentColors: _recentReaderColors,
            ),
          ),
        );
    if (!mounted || selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _readerHorizontalPaddingKey,
      selected.horizontalPadding,
    );
    await prefs.setDouble(_readerVerticalPaddingKey, selected.verticalPadding);
    await prefs.setInt(
      _readerBackgroundColorKey,
      selected.backgroundColor.toARGB32(),
    );
    await prefs.setInt(_readerFontColorKey, selected.fontColor.toARGB32());
    await prefs.setInt(
      _readerHighlightColorKey,
      selected.highlightColor.toARGB32(),
    );
    await prefs.setInt(
      _readerTranslationColorKey,
      selected.translationColor.toARGB32(),
    );
    final recentColors = _mergedRecentColors(selected);
    await prefs.setStringList(
      _readerRecentColorsKey,
      recentColors.map((color) => color.toARGB32().toString()).toList(),
    );
    if (!mounted) return;
    setState(() {
      _horizontalPadding = selected.horizontalPadding;
      _verticalPadding = selected.verticalPadding;
      _customReaderBackgroundColor = selected.backgroundColor;
      _customReaderFontColor = selected.fontColor;
      _customReaderHighlightColor = selected.highlightColor;
      _customReaderTranslationColor = selected.translationColor;
      _recentReaderColors = recentColors;
    });
  }

  List<Color> _mergedRecentColors(_ReaderAdditionalSettings selected) {
    final seen = <int>{};
    final colors = <Color>[];
    for (final color in [
      selected.backgroundColor,
      selected.fontColor,
      selected.highlightColor,
      selected.translationColor,
      ..._recentReaderColors,
    ]) {
      final value = color.toARGB32();
      if (seen.add(value)) {
        colors.add(color);
      }
      if (colors.length >= 12) break;
    }
    return colors;
  }

  Future<void> _confirmResetReaderSettings(VoidCallback refreshSheet) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final palette = context.palette;
        return AlertDialog(
          backgroundColor: palette.elevated,
          title: Text(
            'Сбросить настройки?',
            style: TextStyle(color: palette.text),
          ),
          content: Text(
            'Шрифт, размер, яркость, отступы и цвета чтения вернутся по умолчанию.',
            style: TextStyle(color: palette.mutedText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Отмена', style: TextStyle(color: palette.mutedText)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Сбросить', style: TextStyle(color: palette.danger)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_readerFontPreferenceKey);
    await prefs.remove(_readerHorizontalPaddingKey);
    await prefs.remove(_readerVerticalPaddingKey);
    await prefs.remove(_readerBackgroundColorKey);
    await prefs.remove(_readerFontColorKey);
    await prefs.remove(_readerHighlightColorKey);
    await prefs.remove(_readerTranslationColorKey);
    await prefs.remove(_readerRecentColorsKey);
    if (!mounted) return;
    setState(() {
      _fontSize = 18;
      _brightness = 1.0;
      _readerFontFamily = _systemFontFamily;
      _horizontalPadding = 24;
      _verticalPadding = 24;
      _customReaderBackgroundColor = null;
      _customReaderFontColor = null;
      _customReaderHighlightColor = null;
      _customReaderTranslationColor = null;
      _recentReaderColors = [];
    });
    refreshSheet();
  }

  TextStyle _readerTextStyle(TextStyle style) {
    return _fontPreviewStyle(_readerFontFamily, style);
  }

  TextStyle _fontPreviewStyle(String family, TextStyle style) {
    if (family == _systemFontFamily) {
      return style;
    }
    return GoogleFonts.getFont(family, textStyle: style);
  }
}

class _ReaderFontOption {
  final String name;
  final String family;
  final String note;
  final String sample;
  final bool accessibility;

  const _ReaderFontOption({
    required this.name,
    required this.family,
    required this.note,
    required this.sample,
    this.accessibility = false,
  });
}

const List<_ReaderFontOption> _readerFontOptions = [
  _ReaderFontOption(
    name: 'System',
    family: 'System',
    note: 'Default device font',
    sample: 'A clean default for everyday reading.',
  ),
  _ReaderFontOption(
    name: 'Literata',
    family: 'Literata',
    note: 'Modern book serif',
    sample: 'The page felt calm, open, and easy to stay inside.',
  ),
  _ReaderFontOption(
    name: 'Merriweather',
    family: 'Merriweather',
    note: 'Comfortable long reading',
    sample: 'A steady serif with generous rhythm and clear shapes.',
  ),
  _ReaderFontOption(
    name: 'Lora',
    family: 'Lora',
    note: 'Soft literary serif',
    sample: 'Every sentence keeps a little warmth on the page.',
  ),
  _ReaderFontOption(
    name: 'Libre Baskerville',
    family: 'Libre Baskerville',
    note: 'Classic print feel',
    sample: 'A traditional page voice with strong paragraph texture.',
  ),
  _ReaderFontOption(
    name: 'EB Garamond',
    family: 'EB Garamond',
    note: 'Elegant old-style serif',
    sample: 'The old house stood quiet beneath the winter moon.',
  ),
  _ReaderFontOption(
    name: 'Crimson Text',
    family: 'Crimson Text',
    note: 'Bookish and compact',
    sample: 'A narrow, graceful shape for dense chapters.',
  ),
  _ReaderFontOption(
    name: 'Cormorant Garamond',
    family: 'Cormorant Garamond',
    note: 'Dramatic literary serif',
    sample: 'It gives chapter pages a sharper, more classical voice.',
  ),
  _ReaderFontOption(
    name: 'Source Serif 4',
    family: 'Source Serif 4',
    note: 'Clear editorial serif',
    sample: 'Balanced letters make the paragraph feel composed.',
  ),
  _ReaderFontOption(
    name: 'Noto Serif',
    family: 'Noto Serif',
    note: 'Wide language support',
    sample: 'A reliable serif for mixed-language libraries.',
  ),
  _ReaderFontOption(
    name: 'PT Serif',
    family: 'PT Serif',
    note: 'Strong Cyrillic support',
    sample: 'Русский текст остается плотным и хорошо читаемым.',
  ),
  _ReaderFontOption(
    name: 'Spectral',
    family: 'Spectral',
    note: 'Calm editorial serif',
    sample: 'A refined newspaper-like rhythm for slower reading.',
  ),
  _ReaderFontOption(
    name: 'Vollkorn',
    family: 'Vollkorn',
    note: 'Warm and sturdy',
    sample: 'The letters sit firmly, even at smaller sizes.',
  ),
  _ReaderFontOption(
    name: 'Alegreya',
    family: 'Alegreya',
    note: 'Humanist literary serif',
    sample: 'A page with movement, warmth, and readable contrast.',
  ),
  _ReaderFontOption(
    name: 'Bitter',
    family: 'Bitter',
    note: 'Slab serif clarity',
    sample: 'A little heavier, useful when contrast is low.',
  ),
  _ReaderFontOption(
    name: 'Roboto Slab',
    family: 'Roboto Slab',
    note: 'Modern slab serif',
    sample: 'Crisp and steady without feeling too formal.',
  ),
  _ReaderFontOption(
    name: 'Arvo',
    family: 'Arvo',
    note: 'Geometric slab serif',
    sample: 'Clear shapes that hold up well on bright screens.',
  ),
  _ReaderFontOption(
    name: 'Cardo',
    family: 'Cardo',
    note: 'Classical serif',
    sample: 'A scholarly, older printed-book texture.',
  ),
  _ReaderFontOption(
    name: 'Tinos',
    family: 'Tinos',
    note: 'Times-like serif',
    sample: 'Familiar newspaper proportions for traditional readers.',
  ),
  _ReaderFontOption(
    name: 'Atkinson Hyperlegible',
    family: 'Atkinson Hyperlegible',
    note: 'Accessibility focused',
    sample: 'Distinct letters help reduce visual confusion.',
    accessibility: true,
  ),
  _ReaderFontOption(
    name: 'Lexend',
    family: 'Lexend',
    note: 'Dyslexia-friendly spacing',
    sample: 'Open spacing can make long lines feel less crowded.',
    accessibility: true,
  ),
  _ReaderFontOption(
    name: 'Open Sans',
    family: 'Open Sans',
    note: 'Clean sans serif',
    sample: 'Simple, neutral, and easy for fast scanning.',
  ),
];

class _ReaderFontPickerScreen extends StatelessWidget {
  final String selectedFamily;
  final List<_ReaderFontOption> fonts;

  const _ReaderFontPickerScreen({
    required this.selectedFamily,
    required this.fonts,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: palette.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Шрифт чтения',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        itemCount: fonts.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final font = fonts[index];
          final isSelected = font.family == selectedFamily;
          return _ReaderFontOptionTile(
            font: font,
            isSelected: isSelected,
            onTap: () => Navigator.pop(context, font.family),
          );
        },
      ),
    );
  }
}

class _ReaderFontOptionTile extends StatelessWidget {
  final _ReaderFontOption font;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReaderFontOptionTile({
    required this.font,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final previewStyle = _fontOptionStyle(
      font.family,
      TextStyle(color: palette.text, fontSize: 19, height: 1.45),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? palette.accent.withValues(alpha: 0.14)
              : palette.elevated.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? palette.accent : palette.border,
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    font.name,
                    style: _fontOptionStyle(
                      font.family,
                      TextStyle(
                        color: palette.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (font.accessibility)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.secondaryAccent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'accessibility',
                      style: TextStyle(
                        color: palette.secondaryAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: isSelected ? palette.accent : palette.mutedText,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              font.note,
              style: TextStyle(color: palette.mutedText, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Text(font.sample, style: previewStyle),
          ],
        ),
      ),
    );
  }
}

TextStyle _fontOptionStyle(String family, TextStyle style) {
  if (family == _ReaderScreenState._systemFontFamily) {
    return style;
  }
  return GoogleFonts.getFont(family, textStyle: style);
}

class _ReaderAdditionalSettings {
  final double horizontalPadding;
  final double verticalPadding;
  final Color backgroundColor;
  final Color fontColor;
  final Color highlightColor;
  final Color translationColor;

  const _ReaderAdditionalSettings({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.backgroundColor,
    required this.fontColor,
    required this.highlightColor,
    required this.translationColor,
  });
}

class _ReaderAdditionalSettingsScreen extends StatefulWidget {
  final double horizontalPadding;
  final double verticalPadding;
  final Color backgroundColor;
  final Color fontColor;
  final Color highlightColor;
  final Color translationColor;
  final Color defaultBackgroundColor;
  final Color defaultFontColor;
  final Color defaultHighlightColor;
  final Color defaultTranslationColor;
  final List<Color> recentColors;

  const _ReaderAdditionalSettingsScreen({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.backgroundColor,
    required this.fontColor,
    required this.highlightColor,
    required this.translationColor,
    required this.defaultBackgroundColor,
    required this.defaultFontColor,
    required this.defaultHighlightColor,
    required this.defaultTranslationColor,
    required this.recentColors,
  });

  @override
  State<_ReaderAdditionalSettingsScreen> createState() =>
      _ReaderAdditionalSettingsScreenState();
}

class _ReaderAdditionalSettingsScreenState
    extends State<_ReaderAdditionalSettingsScreen> {
  late double _horizontalPadding = widget.horizontalPadding;
  late double _verticalPadding = widget.verticalPadding;
  late Color _backgroundColor = widget.backgroundColor;
  late Color _fontColor = widget.fontColor;
  late Color _highlightColor = widget.highlightColor;
  late Color _translationColor = widget.translationColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: palette.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Дополнительно',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _ReaderAdditionalSettings(
                horizontalPadding: _horizontalPadding,
                verticalPadding: _verticalPadding,
                backgroundColor: _backgroundColor,
                fontColor: _fontColor,
                highlightColor: _highlightColor,
                translationColor: _translationColor,
              ),
            ),
            child: Text(
              'Готово',
              style: TextStyle(
                color: palette.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          _SettingsSectionLabel('Отступы'),
          _SectionResetButton(
            label: 'Вернуть отступы по умолчанию',
            onPressed: () => setState(() {
              _horizontalPadding = 24;
              _verticalPadding = 24;
            }),
          ),
          const SizedBox(height: 10),
          _PaddingPreviewCard(
            horizontalPadding: _horizontalPadding,
            verticalPadding: _verticalPadding,
            backgroundColor: _backgroundColor,
            fontColor: _fontColor,
            highlightColor: _highlightColor,
          ),
          const SizedBox(height: 20),
          _PaddingSliderCard(
            icon: Icons.swap_horiz_rounded,
            label: 'Горизонтальные',
            value: _horizontalPadding,
            min: 12,
            max: 56,
            divisions: 11,
            onChanged: (value) => setState(() => _horizontalPadding = value),
          ),
          const SizedBox(height: 14),
          _PaddingSliderCard(
            icon: Icons.swap_vert_rounded,
            label: 'Вертикальные',
            value: _verticalPadding,
            min: 12,
            max: 64,
            divisions: 13,
            onChanged: (value) => setState(() => _verticalPadding = value),
          ),
          const SizedBox(height: 26),
          _SettingsSectionLabel('Цвета'),
          _SectionResetButton(
            label: 'Вернуть цвета по умолчанию',
            onPressed: () => setState(() {
              _backgroundColor = widget.defaultBackgroundColor;
              _fontColor = widget.defaultFontColor;
              _highlightColor = widget.defaultHighlightColor;
              _translationColor = widget.defaultTranslationColor;
            }),
          ),
          const SizedBox(height: 10),
          _ReaderColorTile(
            label: 'Фон',
            color: _backgroundColor,
            recentColors: widget.recentColors,
            onChanged: (color) => setState(() => _backgroundColor = color),
          ),
          const SizedBox(height: 12),
          _ReaderColorTile(
            label: 'Текст',
            color: _fontColor,
            recentColors: widget.recentColors,
            onChanged: (color) => setState(() => _fontColor = color),
          ),
          const SizedBox(height: 12),
          _ReaderColorTile(
            label: 'Выделение',
            color: _highlightColor,
            recentColors: widget.recentColors,
            onChanged: (color) => setState(() => _highlightColor = color),
          ),
          const SizedBox(height: 12),
          _ReaderColorTile(
            label: 'Сохранённый перевод',
            color: _translationColor,
            recentColors: widget.recentColors,
            onChanged: (color) => setState(() => _translationColor = color),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String text;

  const _SettingsSectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      text,
      style: TextStyle(
        color: palette.text,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SectionResetButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SectionResetButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.restart_alt_rounded, size: 15, color: palette.accent),
        label: Text(
          label,
          style: TextStyle(
            color: palette.accent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _PaddingPreviewCard extends StatelessWidget {
  final double horizontalPadding;
  final double verticalPadding;
  final Color backgroundColor;
  final Color fontColor;
  final Color highlightColor;

  const _PaddingPreviewCard({
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.backgroundColor,
    required this.fontColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: AspectRatio(
        aspectRatio: 0.72,
        child: Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding * 0.55,
              vertical: verticalPadding * 0.55,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 96,
                  height: 14,
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                for (final entry in const [1.0, 0.82, 0.94, 0.74, 0.88].indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FractionallySizedBox(
                      widthFactor: entry.$2,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: entry.$1 == 1
                              ? highlightColor.withValues(alpha: 0.46)
                              : fontColor.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaddingSliderCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _PaddingSliderCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: palette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                value.round().toString(),
                style: TextStyle(
                  color: palette.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: palette.accent,
            inactiveColor: palette.border,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ReaderColorTile extends StatefulWidget {
  final String label;
  final Color color;
  final List<Color> recentColors;
  final ValueChanged<Color> onChanged;

  const _ReaderColorTile({
    required this.label,
    required this.color,
    required this.recentColors,
    required this.onChanged,
  });

  @override
  State<_ReaderColorTile> createState() => _ReaderColorTileState();
}

class _ReaderColorTileState extends State<_ReaderColorTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.border, width: 1.4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _hex(widget.color),
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: palette.mutedText,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _ReaderColorEditor(
                color: widget.color,
                recentColors: widget.recentColors,
                onChanged: widget.onChanged,
              ),
            ),
        ],
      ),
    );
  }

  String _hex(Color color) {
    final value = color.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

class _ReaderColorEditor extends StatefulWidget {
  final Color color;
  final List<Color> recentColors;
  final ValueChanged<Color> onChanged;

  const _ReaderColorEditor({
    required this.color,
    required this.recentColors,
    required this.onChanged,
  });

  @override
  State<_ReaderColorEditor> createState() => _ReaderColorEditorState();
}

class _ReaderColorEditorState extends State<_ReaderColorEditor> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);

  @override
  void didUpdateWidget(covariant _ReaderColorEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _hsv = HSVColor.fromColor(widget.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.recentColors.isNotEmpty) ...[
          Text(
            'Недавние',
            style: TextStyle(color: palette.mutedText, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in widget.recentColors)
                _RecentColorButton(
                  color: color,
                  selected: color.toARGB32() == widget.color.toARGB32(),
                  onTap: () => _setColor(color),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        _SaturationValuePicker(
          hsv: _hsv,
          onChanged: (saturation, value) {
            _updateHsv(_hsv.withSaturation(saturation).withValue(value));
          },
        ),
        const SizedBox(height: 12),
        _HueStrip(
          hue: _hsv.hue,
          onChanged: (hue) => _updateHsv(_hsv.withHue(hue)),
        ),
        const SizedBox(height: 12),
        _ColorValueFields(color: widget.color, onChanged: _setColor),
      ],
    );
  }

  void _updateHsv(HSVColor hsv) {
    setState(() => _hsv = hsv);
    widget.onChanged(hsv.toColor().withAlpha(255));
  }

  void _setColor(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color));
    widget.onChanged(color.withAlpha(255));
  }
}

class _RecentColorButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _RecentColorButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 2.4 : 1.2,
          ),
        ),
      ),
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  final HSVColor hsv;
  final void Function(double saturation, double value) onChanged;

  const _SaturationValuePicker({required this.hsv, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 180.0;
        return GestureDetector(
          onPanDown: (details) => _select(details.localPosition, width, height),
          onPanUpdate: (details) =>
              _select(details.localPosition, width, height),
          child: Stack(
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: hueColor,
                  border: Border.all(color: context.palette.border),
                ),
              ),
              Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Colors.white, Colors.transparent],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Container(
                height: height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Colors.transparent, Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              Positioned(
                left: (hsv.saturation * width).clamp(0.0, width) - 8,
                top: ((1 - hsv.value) * height).clamp(0.0, height) - 8,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _select(Offset position, double width, double height) {
    final saturation = (position.dx / width).clamp(0.0, 1.0);
    final value = (1 - position.dy / height).clamp(0.0, 1.0);
    onChanged(saturation, value);
  }
}

class _HueStrip extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueStrip({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanDown: (details) => _select(details.localPosition.dx, width),
          onPanUpdate: (details) => _select(details.localPosition.dx, width),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFFF0000),
                      Color(0xFFFFFF00),
                      Color(0xFF00FF00),
                      Color(0xFF00FFFF),
                      Color(0xFF0000FF),
                      Color(0xFFFF00FF),
                      Color(0xFFFF0000),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: (hue / 360 * width).clamp(0.0, width) - 7,
                child: Container(
                  width: 14,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _select(double dx, double width) {
    onChanged((dx / width * 360).clamp(0.0, 360.0));
  }
}

class _ColorValueFields extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onChanged;

  const _ColorValueFields({required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final argb = color.toARGB32();
    final red = (argb >> 16) & 0xFF;
    final green = (argb >> 8) & 0xFF;
    final blue = argb & 0xFF;
    final hex =
        '#${((red << 16) | (green << 8) | blue).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ColorTextField(
          label: 'HEX',
          value: hex,
          width: 116,
          onCommit: (value) {
            final parsed = _parseHex(value);
            if (parsed != null) onChanged(parsed);
          },
        ),
        _RgbNumberField(
          label: 'R',
          value: red,
          onChanged: (value) =>
              onChanged(Color.fromARGB(255, value, green, blue)),
        ),
        _RgbNumberField(
          label: 'G',
          value: green,
          onChanged: (value) =>
              onChanged(Color.fromARGB(255, red, value, blue)),
        ),
        _RgbNumberField(
          label: 'B',
          value: blue,
          onChanged: (value) =>
              onChanged(Color.fromARGB(255, red, green, value)),
        ),
        Text(
          'RGB',
          style: TextStyle(
            color: palette.mutedText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Color? _parseHex(String raw) {
    final normalized = raw.trim().replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}

class _ColorTextField extends StatefulWidget {
  final String label;
  final String value;
  final double width;
  final ValueChanged<String> onCommit;

  const _ColorTextField({
    required this.label,
    required this.value,
    required this.width,
    required this.onCommit,
  });

  @override
  State<_ColorTextField> createState() => _ColorTextFieldState();
}

class _ColorTextFieldState extends State<_ColorTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _ColorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: widget.width,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        style: TextStyle(color: palette.text, fontWeight: FontWeight.w700),
        keyboardType: widget.label == 'HEX'
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: false),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(color: palette.mutedText, fontSize: 12),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: palette.border),
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: palette.accent),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onChanged: _commit,
        onFieldSubmitted: _submit,
        onTapOutside: (_) => _submit(_controller.text),
      ),
    );
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit(_controller.text);
    }
  }

  void _commit(String value) {
    widget.onCommit(value);
  }

  void _submit(String value) {
    _commit(value);
    _focusNode.unfocus();
  }
}

class _RgbNumberField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _RgbNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _ColorTextField(
      label: label,
      value: value.toString(),
      width: 58,
      onCommit: (raw) {
        final parsed = int.tryParse(raw.trim());
        if (parsed == null) return;
        onChanged(parsed.clamp(0, 255));
      },
    );
  }
}

class _ReviewsSheet extends StatefulWidget {
  final String token;
  final int bookId;
  final String bookTitle;
  final int initialRating;
  final ValueChanged<int> onRatingChanged;

  const _ReviewsSheet({
    required this.token,
    required this.bookId,
    required this.bookTitle,
    required this.initialRating,
    required this.onRatingChanged,
  });

  @override
  State<_ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<_ReviewsSheet> {
  final CommunityService _service = CommunityService();
  final TextEditingController _reviewController = TextEditingController();
  List<CommunityReview> _reviews = [];
  bool _isLoading = true;
  bool _isSaving = false;
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _load();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final reviews = await _service.getReviews(widget.token, widget.bookId);
      final mine = reviews.where((review) => review.currentUserReview).toList();
      if (mine.isNotEmpty) {
        _reviewController.text = mine.first.text;
        _rating = mine.first.rating;
      }
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: context.palette.danger),
      );
    }
  }

  Future<void> _saveReview() async {
    final text = _reviewController.text.trim();
    if (_isSaving || text.isEmpty || _rating < 1) return;
    setState(() => _isSaving = true);
    try {
      await _service.saveReview(
        token: widget.token,
        bookId: widget.bookId,
        rating: _rating,
        text: text,
      );
      widget.onRatingChanged(_rating);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: context.palette.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _replyTo(int reviewId, {int? parentReplyId}) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        final palette = context.palette;
        return AlertDialog(
          backgroundColor: palette.elevated,
          title: Text('Ответить', style: TextStyle(color: palette.text)),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(color: palette.text),
            decoration: const InputDecoration(hintText: 'Ваш ответ'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Отмена', style: TextStyle(color: palette.mutedText)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Опубликовать'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    await _service.createReply(
      token: widget.token,
      bookId: widget.bookId,
      reviewId: reviewId,
      parentReplyId: parentReplyId,
      text: text,
    );
    await _load();
  }

  Future<void> _voteReview(CommunityReview review, int vote) async {
    await _service.voteReview(
      widget.token,
      widget.bookId,
      review.id,
      review.currentUserVote == vote ? 0 : vote,
    );
    await _load();
  }

  Future<void> _voteReply(CommunityReply reply, int vote) async {
    await _service.voteReply(
      widget.token,
      widget.bookId,
      reply.id,
      reply.currentUserVote == vote ? 0 : vote,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.border),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
            const SizedBox(height: 16),
            Text(
              'Отзывы',
              style: TextStyle(
                color: palette.text,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            _ReviewComposer(
              controller: _reviewController,
              rating: _rating,
              isSaving: _isSaving,
              onRatingChanged: (rating) => setState(() => _rating = rating),
              onSave: _saveReview,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: palette.accent),
                    )
                  : _reviews.isEmpty
                  ? Center(
                      child: Text(
                        'Пока нет отзывов.',
                        style: TextStyle(color: palette.mutedText),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _reviews.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final review = _reviews[index];
                        return _ReviewCard(
                          review: review,
                          onVote: (vote) => _voteReview(review, vote),
                          onReply: () => _replyTo(review.id),
                          onReplyVote: _voteReply,
                          onReplyToReply: (reply) =>
                              _replyTo(review.id, parentReplyId: reply.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewComposer extends StatelessWidget {
  final TextEditingController controller;
  final int rating;
  final bool isSaving;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSave;

  const _ReviewComposer({
    required this.controller,
    required this.rating,
    required this.isSaving,
    required this.onRatingChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onRatingChanged(star),
                  icon: Icon(
                    star <= rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: palette.warning,
                  ),
                ),
              const Spacer(),
              ElevatedButton(
                onPressed: isSaving ? null : onSave,
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Опубликовать'),
              ),
            ],
          ),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: palette.text),
            decoration: InputDecoration(
              hintText: 'Напишите отзыв',
              hintStyle: TextStyle(color: palette.mutedText),
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final CommunityReview review;
  final ValueChanged<int> onVote;
  final VoidCallback onReply;
  final ValueChanged<CommunityReply> onReplyToReply;
  final void Function(CommunityReply reply, int vote) onReplyVote;

  const _ReviewCard({
    required this.review,
    required this.onVote,
    required this.onReply,
    required this.onReplyToReply,
    required this.onReplyVote,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AuthorRow(
            nickname: review.nickname,
            initial: review.avatarInitial,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var star = 1; star <= 5; star++)
                  Icon(
                    star <= review.rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: palette.warning,
                    size: 16,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _ExpandableText(review.text),
          const SizedBox(height: 8),
          _ActionsRow(
            likes: review.likes,
            dislikes: review.dislikes,
            currentVote: review.currentUserVote,
            onVote: onVote,
            onReply: onReply,
          ),
          for (final reply in review.replies)
            _ReplyCard(
              reply: reply,
              depth: 1,
              onVote: onReplyVote,
              onReply: onReplyToReply,
            ),
        ],
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  final CommunityReply reply;
  final int depth;
  final void Function(CommunityReply reply, int vote) onVote;
  final ValueChanged<CommunityReply> onReply;

  const _ReplyCard({
    required this.reply,
    required this.depth,
    required this.onVote,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: (depth.clamp(1, 4) * 14).toDouble(),
        top: 10,
      ),
      child: Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: palette.border, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthorRow(nickname: reply.nickname, initial: reply.avatarInitial),
            const SizedBox(height: 8),
            _ExpandableText(reply.text),
            _ActionsRow(
              likes: reply.likes,
              dislikes: reply.dislikes,
              currentVote: reply.currentUserVote,
              onVote: (vote) => onVote(reply, vote),
              onReply: () => onReply(reply),
            ),
            for (final child in reply.replies)
              _ReplyCard(
                reply: child,
                depth: depth + 1,
                onVote: onVote,
                onReply: onReply,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  final int likes;
  final int dislikes;
  final int currentVote;
  final ValueChanged<int> onVote;
  final VoidCallback onReply;

  const _ActionsRow({
    required this.likes,
    required this.dislikes,
    required this.currentVote,
    required this.onVote,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onVote(1),
          icon: Icon(
            Icons.thumb_up_alt_rounded,
            size: 18,
            color: currentVote == 1 ? palette.accent : palette.mutedText,
          ),
        ),
        Text('$likes', style: TextStyle(color: palette.mutedText)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onVote(-1),
          icon: Icon(
            Icons.thumb_down_alt_rounded,
            size: 18,
            color: currentVote == -1 ? palette.danger : palette.mutedText,
          ),
        ),
        Text('$dislikes', style: TextStyle(color: palette.mutedText)),
        TextButton.icon(
          onPressed: onReply,
          icon: Icon(Icons.reply_rounded, size: 18, color: palette.mutedText),
          label: Text('Ответить', style: TextStyle(color: palette.mutedText)),
        ),
      ],
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final String nickname;
  final String initial;
  final Widget? trailing;

  const _AuthorRow({
    required this.nickname,
    required this.initial,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: palette.accent.withValues(alpha: 0.18),
          child: Text(
            initial.isEmpty ? 'U' : initial[0].toUpperCase(),
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            nickname,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText(this.text);

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final words = widget.text.trim().split(RegExp(r'\s+'));
    final shouldCut = words.length > 80;
    final shown = shouldCut && !_expanded
        ? '${words.take(80).join(' ')}...'
        : widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(shown, style: TextStyle(color: palette.text, height: 1.42)),
        if (shouldCut)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Скрыть' : 'Показать больше',
              style: TextStyle(color: palette.accent),
            ),
          ),
      ],
    );
  }
}

class _QuotesSheet extends StatefulWidget {
  final String token;
  final int bookId;

  const _QuotesSheet({required this.token, required this.bookId});

  @override
  State<_QuotesSheet> createState() => _QuotesSheetState();
}

class _QuotesSheetState extends State<_QuotesSheet> {
  final CommunityService _service = CommunityService();
  List<FavoriteQuote> _quotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final quotes = await _service.getBookQuotes(widget.token, widget.bookId);
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: context.palette.danger),
      );
    }
  }

  Future<void> _vote(FavoriteQuote quote, int vote) async {
    await _service.voteQuote(
      widget.token,
      widget.bookId,
      quote.id,
      quote.currentUserVote == vote ? 0 : vote,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.border),
      ),
      child: SafeArea(
        top: false,
        child: Column(
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
            const SizedBox(height: 16),
            Text(
              'Цитаты',
              style: TextStyle(
                color: palette.text,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: palette.accent),
                    )
                  : _quotes.isEmpty
                  ? Center(
                      child: Text(
                        'Пока нет опубликованных цитат.',
                        style: TextStyle(color: palette.mutedText),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _quotes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final quote = _quotes[index];
                        return _QuoteCard(
                          quote: quote,
                          onVote: (vote) => _vote(quote, vote),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteCard extends StatefulWidget {
  final FavoriteQuote quote;
  final ValueChanged<int> onVote;

  const _QuoteCard({required this.quote, required this.onVote});

  @override
  State<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends State<_QuoteCard> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quote = widget.quote;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _showDetails = !_showDetails),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: 0.50),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              quote.text,
              style: TextStyle(
                color: palette.text,
                height: 1.45,
                fontStyle: FontStyle.italic,
              ),
            ),
            if (_showDetails) ...[
              const SizedBox(height: 10),
              Text(
                'Глава ${quote.chapterOrder} · ${quote.nickname}',
                style: TextStyle(color: palette.mutedText, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onVote(1),
                  icon: Icon(
                    Icons.thumb_up_alt_rounded,
                    color: quote.currentUserVote == 1
                        ? palette.accent
                        : palette.mutedText,
                    size: 18,
                  ),
                ),
                Text(
                  '${quote.likes}',
                  style: TextStyle(color: palette.mutedText),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => widget.onVote(-1),
                  icon: Icon(
                    Icons.thumb_down_alt_rounded,
                    color: quote.currentUserVote == -1
                        ? palette.danger
                        : palette.mutedText,
                    size: 18,
                  ),
                ),
                Text(
                  '${quote.dislikes}',
                  style: TextStyle(color: palette.mutedText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LookupSheet extends StatefulWidget {
  final LookupResult result;
  final String selectedText;
  final Future<void> Function() onSave;

  const _LookupSheet({
    required this.result,
    required this.selectedText,
    required this.onSave,
  });

  @override
  State<_LookupSheet> createState() => _LookupSheetState();
}

class _LookupSheetState extends State<_LookupSheet> {
  bool _isSaving = false;

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final result = widget.result;
    final translation = result.translation?.text.trim();
    final hasTranslation = translation != null && translation.isNotEmpty;
    final translationAlternatives =
        result.translation?.alternatives
            .where((item) => item.trim().isNotEmpty)
            .toList() ??
        const [];
    final maxHeight = MediaQuery.of(context).size.height * 0.82;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
      decoration: BoxDecoration(
        color: palette.elevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.36 : 0.14),
            blurRadius: 24,
            offset: const Offset(0, -10),
          ),
        ],
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
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD166).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFFFFD166),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Словарь',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${result.detectedLanguage.toUpperCase()} → ${result.targetLanguage.toUpperCase()}',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LookupSection(
                      title: 'Выделено',
                      child: Text(
                        widget.selectedText,
                        style: TextStyle(
                          color: palette.text,
                          height: 1.45,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _LookupSection(
                      title: 'Определения',
                      child: result.definitions.isEmpty
                          ? Text(
                              'Для фраз показывается только перевод. Для слова определение может отсутствовать в источнике.',
                              style: TextStyle(
                                color: palette.mutedText,
                                height: 1.35,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final definition in result.definitions)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _DefinitionView(
                                      definition: definition,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    _LookupSection(
                      title: 'Перевод',
                      child: hasTranslation
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  translation,
                                  style: TextStyle(
                                    color: palette.text,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (translationAlternatives.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Варианты',
                                    style: TextStyle(
                                      color: palette.mutedText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  for (final alternative
                                      in translationAlternatives)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '- ',
                                            style: TextStyle(
                                              color: palette.mutedText,
                                              height: 1.35,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              alternative,
                                              style: TextStyle(
                                                color: palette.text,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ],
                            )
                          : Text(
                              'Перевод сейчас недоступен.',
                              style: TextStyle(color: palette.mutedText),
                            ),
                    ),
                    if (result.errors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _LookupSection(
                        title: 'Статус',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final error in result.errors)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  error,
                                  style: TextStyle(
                                    color: palette.warning,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Закрыть',
                      style: TextStyle(color: palette.mutedText),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.onAccent,
                            ),
                          )
                        : const Icon(Icons.bookmark_add_rounded),
                    label: const Text('Сохранить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD166),
                      foregroundColor: const Color(0xFF1B1B1B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LookupSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _LookupSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isDark ? 0.42 : 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _DefinitionView extends StatelessWidget {
  final LookupDefinition definition;

  const _DefinitionView({required this.definition});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final partOfSpeech = definition.partOfSpeech.trim();
    final example = definition.example.trim();
    final source = definition.source.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (partOfSpeech.isNotEmpty)
          Text(
            partOfSpeech,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        Text(
          definition.definition,
          style: TextStyle(color: palette.text, height: 1.42),
        ),
        if (example.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            example,
            style: TextStyle(
              color: palette.mutedText,
              height: 1.35,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (source.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            source,
            style: TextStyle(
              color: palette.mutedText.withValues(alpha: 0.72),
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _AnnotationNoteSheet extends StatefulWidget {
  final BookAnnotation annotation;

  const _AnnotationNoteSheet({required this.annotation});

  @override
  State<_AnnotationNoteSheet> createState() => _AnnotationNoteSheetState();
}

class _AnnotationNoteSheetState extends State<_AnnotationNoteSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.annotation.note);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        decoration: BoxDecoration(
          color: palette.elevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              const SizedBox(height: 20),
              Text(
                'Заметка к выделению',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.highlight.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: palette.accent.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  widget.annotation.highlightedText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text.withValues(alpha: 0.86),
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 5,
                style: TextStyle(color: palette.text),
                decoration: InputDecoration(
                  hintText: 'Добавьте мысль, вопрос или короткую заметку...',
                  hintStyle: TextStyle(
                    color: palette.mutedText.withValues(alpha: 0.70),
                  ),
                  filled: true,
                  fillColor: palette.surface.withValues(
                    alpha: palette.isDark ? 0.44 : 0.72,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.accent),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Позже',
                        style: TextStyle(color: palette.mutedText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
