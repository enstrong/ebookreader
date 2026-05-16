import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ebookreader/models/book_annotation.dart';
import 'package:ebookreader/services/annotation_service.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';

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

  const ReaderScreen({
    super.key,
    required this.token,
    required this.bookId,
    required this.chapterOrder,
    this.initialSegmentProgress = 0.0,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();
  final AnnotationService _annotationService = AnnotationService();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _chapter;
  List<BookAnnotation> _annotations = [];
  int _currentChapter = 1;
  int _totalChapters = 0;
  bool _isLoading = true;
  bool _showControls = true;
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
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
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
      final chapters = await _bookService.getBookChapters(
        widget.token,
        widget.bookId,
      );
      final annotations = await _annotationService.getChapterAnnotations(
        widget.token,
        widget.bookId,
        _currentChapter,
      );

      await _saveTextProgress();

      if (!mounted) return;
      setState(() {
        _chapter = chapter;
        _annotations = annotations;
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
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.72,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFF10162F),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Выделения и заметки',
                        style: TextStyle(
                          color: Colors.white,
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
                        color: const Color(0xFF14FFEC).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${allAnnotations.length}',
                        style: const TextStyle(
                          color: Color(0xFF14FFEC),
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
                              color: Colors.white.withValues(alpha: 0.58),
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
        ),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: _showControls
          ? AppBar(
              backgroundColor: const Color(0xFF1A1F3A),
              elevation: 0,
              title: Text(
                _chapter?['title'] ?? 'Глава $_currentChapter',
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.border_color_rounded,
                        color: Color(0xFF14FFEC),
                      ),
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
                  icon: const Icon(Icons.settings, color: Color(0xFF14FFEC)),
                  onPressed: _showFontSettings,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: const Color(0xFF14FFEC),
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
                    colors: [const Color(0xFF0A0E27), const Color(0xFF1A1F3A)],
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
                                    Colors.white.withValues(alpha: 0.05),
                                    Colors.white.withValues(alpha: 0.02),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
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
                                      color: const Color(0xFF14FFEC),
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
                                      color: Colors.white,
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
                              gradient: const LinearGradient(
                                colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                              ),
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF14FFEC,
                                  ).withValues(alpha: 0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: TextButton.icon(
                              onPressed: _createHighlight,
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                color: Colors.black,
                              ),
                              label: const Text(
                                'Выделить',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
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
                                    const Color(
                                      0xFF1A1F3A,
                                    ).withValues(alpha: 0.95),
                                    const Color(0xFF0A0E27),
                                  ],
                                ),
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.1),
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
                                                    Colors.white.withValues(
                                                      alpha: 0.1,
                                                    ),
                                                    Colors.white.withValues(
                                                      alpha: 0.05,
                                                    ),
                                                  ],
                                                )
                                              : null,
                                          color: _currentChapter <= 1
                                              ? Colors.white.withValues(
                                                  alpha: 0.03,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.1,
                                            ),
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
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                    alpha: 0.3,
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
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF14FFEC),
                                              Color(0xFF0D7377),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '$_currentChapter/$_totalChapters',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
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
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF14FFEC),
                                                    Color(0xFF0D7377),
                                                  ],
                                                )
                                              : null,
                                          color:
                                              _currentChapter >= _totalChapters
                                              ? Colors.white.withValues(
                                                  alpha: 0.03,
                                                )
                                              : null,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border:
                                              _currentChapter >= _totalChapters
                                              ? Border.all(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.1),
                                                  width: 1.5,
                                                )
                                              : null,
                                          boxShadow:
                                              _currentChapter < _totalChapters
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF14FFEC,
                                                    ).withValues(alpha: 0.3),
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
                                                ? Colors.white
                                                : Colors.white.withValues(
                                                    alpha: 0.3,
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
    final content = _chapter?['content']?.toString() ?? '';
    final baseStyle = TextStyle(
      fontSize: _fontSize,
      height: 1.9,
      color: Colors.white.withValues(alpha: 0.85),
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

      if (start > cursor) {
        spans.add(
          TextSpan(text: content.substring(cursor, start), style: baseStyle),
        );
      }
      spans.add(
        TextSpan(
          text: content.substring(start, end),
          style: baseStyle.copyWith(
            color: Colors.white,
            backgroundColor: const Color(0xFF14FFEC).withValues(alpha: 0.22),
            decoration: TextDecoration.underline,
            decorationColor: const Color(0xFF14FFEC).withValues(alpha: 0.65),
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
    return Material(
      color: Colors.white.withValues(alpha: 0.055),
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
                      color: const Color(0xFF14FFEC).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Глава ${annotation.chapterOrder}',
                      style: const TextStyle(
                        color: Color(0xFF14FFEC),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white70,
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
                  color: Colors.white.withValues(alpha: 0.86),
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
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    height: 1.35,
                  ),
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
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [const Color(0xFF1A1F3A), const Color(0xFF0A0E27)],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Настройки чтения',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                // Font size
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF14FFEC).withValues(alpha: 0.2),
                            const Color(0xFF0D7377).withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.format_size,
                        color: Color(0xFF14FFEC),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Размер шрифта',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                          ),
                          Slider(
                            value: _fontSize,
                            min: 14,
                            max: 28,
                            divisions: 7,
                            activeColor: const Color(0xFF14FFEC),
                            inactiveColor: Colors.white.withValues(alpha: 0.1),
                            onChanged: (value) {
                              setState(() => _fontSize = value);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_fontSize.round()}',
                      style: const TextStyle(
                        color: Color(0xFF14FFEC),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Brightness
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF14FFEC).withValues(alpha: 0.2),
                            const Color(0xFF0D7377).withValues(alpha: 0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.brightness_6,
                        color: Color(0xFF14FFEC),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Яркость',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                          ),
                          Slider(
                            value: _brightness,
                            min: 0.5,
                            max: 1.0,
                            activeColor: const Color(0xFF14FFEC),
                            inactiveColor: Colors.white.withValues(alpha: 0.1),
                            onChanged: (value) {
                              setState(() => _brightness = value);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF10162F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Заметка к выделению',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  widget.annotation.highlightedText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
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
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Добавьте мысль, вопрос или короткую заметку...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF14FFEC)),
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
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14FFEC),
                        foregroundColor: Colors.black,
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
