import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ebookreader/models/book_annotation.dart';
import 'package:ebookreader/models/lookup_result.dart';
import 'package:ebookreader/services/annotation_service.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:ebookreader/services/lookup_service.dart';
import 'package:ebookreader/theme/app_theme.dart';

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
  final LookupService _lookupService = LookupService();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _chapter;
  String _bookTitle = '';
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
  double _segmentProgress = 0.0;
  BookAnnotation? _pendingScrollAnnotation;
  Timer? _progressSaveTimer;
  bool _restoredInitialScroll = false;
  late AnimationController _animController;

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
      final annotations = await _annotationService.getChapterAnnotations(
        widget.token,
        widget.bookId,
        _currentChapter,
      );
      final progress = await _bookmarkService.getProgress(
        widget.token,
        widget.bookId,
      );

      await _saveTextProgress();

      if (!mounted) return;
      setState(() {
        _chapter = chapter;
        _bookTitle = book['title']?.toString() ?? '';
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
        color: '#FFD166',
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

  Color _annotationColor(String rawColor) {
    final normalized = rawColor.trim().replaceFirst('#', '');
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      return context.palette.highlight;
    }
    return Color(0xFF000000 | value);
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
              onTap: _toggleControls,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.background, palette.surface],
                  ),
                ),
                child: Opacity(
                  opacity: _brightness,
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          24,
                          _showControls ? 24 : 80,
                          24,
                          120,
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
                                    style: TextStyle(
                                      fontSize: _fontSize + 6,
                                      fontWeight: FontWeight.bold,
                                      color: palette.text,
                                      height: 1.4,
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
                                  children: [
                                    // Previous button
                                    Expanded(
                                      child: Container(
                                        height: 50,
                                        decoration: BoxDecoration(
                                          gradient: _currentChapter > 1
                                              ? LinearGradient(
                                                  colors: [
                                                    palette.text.withValues(
                                                      alpha: palette.isDark
                                                          ? 0.10
                                                          : 0.08,
                                                    ),
                                                    palette.text.withValues(
                                                      alpha: palette.isDark
                                                          ? 0.05
                                                          : 0.04,
                                                    ),
                                                  ],
                                                )
                                              : null,
                                          color: _currentChapter <= 1
                                              ? palette.text.withValues(
                                                  alpha: palette.isDark
                                                      ? 0.03
                                                      : 0.05,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: palette.border,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: _currentChapter > 1
                                              ? _prevChapter
                                              : null,
                                          icon: const Icon(
                                            Icons.arrow_back_rounded,
                                          ),
                                          label: const Text('Назад'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: _currentChapter > 1
                                                ? palette.text
                                                : palette.mutedText.withValues(
                                                    alpha: 0.45,
                                                  ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Chapter counter
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
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

                                    // Next button
                                    Expanded(
                                      child: Container(
                                        height: 50,
                                        decoration: BoxDecoration(
                                          gradient:
                                              _currentChapter < _totalChapters
                                              ? palette.accentGradient
                                              : null,
                                          color:
                                              _currentChapter >= _totalChapters
                                              ? palette.text.withValues(
                                                  alpha: palette.isDark
                                                      ? 0.03
                                                      : 0.05,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border:
                                              _currentChapter >= _totalChapters
                                              ? Border.all(
                                                  color: palette.border,
                                                  width: 1.5,
                                                )
                                              : null,
                                          boxShadow:
                                              _currentChapter < _totalChapters
                                              ? [
                                                  BoxShadow(
                                                    color: palette.accent
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 15,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              _currentChapter < _totalChapters
                                              ? _nextChapter
                                              : null,
                                          icon: const Icon(
                                            Icons.arrow_forward_rounded,
                                          ),
                                          label: const Text('Вперёд'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor:
                                                _currentChapter < _totalChapters
                                                ? palette.onAccent
                                                : palette.mutedText.withValues(
                                                    alpha: 0.45,
                                                  ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  TextSpan _buildHighlightedContent() {
    final palette = context.palette;
    final content = _chapter?['content']?.toString() ?? '';
    final baseStyle = TextStyle(
      fontSize: _fontSize,
      height: 1.9,
      color: palette.text.withValues(alpha: 0.88),
      letterSpacing: 0.3,
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
      final annotationColor = _annotationColor(annotation.color);

      if (start > cursor) {
        spans.add(
          TextSpan(text: content.substring(cursor, start), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: content.substring(start, end),
          style: baseStyle.copyWith(
            color: palette.text,
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

  Widget _buildAnnotationCard(
    BookAnnotation annotation, {
    required VoidCallback onTap,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    final palette = context.palette;
    final annotationColor = _annotationColor(annotation.color);
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
                  color: palette.text.withValues(alpha: 0.86),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final palette = context.palette;
          return Container(
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
                ],
              ),
            ),
          );
        },
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
                          ? Text(
                              translation,
                              style: TextStyle(
                                color: palette.text,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
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
