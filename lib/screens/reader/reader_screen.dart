import 'dart:async';

import 'package:flutter/material.dart';
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

class _ReaderScreenState extends State<ReaderScreen> with SingleTickerProviderStateMixin {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic>? _chapter;
  int _currentChapter = 1;
  int _totalChapters = 0;
  bool _isLoading = true;
  bool _showControls = true;
  double _fontSize = 18;
  double _brightness = 1.0;
  double _segmentProgress = 0.0;
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
    final chapters = await _bookService.getBookChapters(widget.token, widget.bookId);
    
    await _saveTextProgress();

    setState(() {
      _chapter = chapter;
      _totalChapters = chapters.length;
      _isLoading = false;
    });
    
    // ✅ ИСПРАВЛЕНО: Прокручиваем только после отрисовки виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final shouldRestore = !_restoredInitialScroll && _segmentProgress > 0;
        _scrollController.jumpTo(shouldRestore ? maxScroll * _segmentProgress : 0);
        _restoredInitialScroll = true;
      }
    });
    
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

  void _nextChapter() {
    if (_currentChapter < _totalChapters) {
      setState(() {
        _currentChapter++;
        _segmentProgress = 0.0;
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
        _restoredInitialScroll = true;
      });
      _loadChapter();
    }
  }

  void _onScrollProgressChanged() {
    if (!_scrollController.hasClients || _isLoading) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      _segmentProgress = 0.0;
    } else {
      _segmentProgress = (_scrollController.offset / maxScroll).clamp(0.0, 1.0).toDouble();
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
                    colors: [
                      const Color(0xFF0A0E27),
                      const Color(0xFF1A1F3A),
                    ],
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
                            Text(
                              _chapter?['content'] ?? '',
                              style: TextStyle(
                                fontSize: _fontSize,
                                height: 1.9,
                                color: Colors.white.withValues(alpha: 0.85),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
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
                                offset: Offset(0, 100 * (1 - _animController.value)),
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
                                    const Color(0xFF1A1F3A).withValues(alpha: 0.95),
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
                                                    Colors.white.withValues(alpha: 0.1),
                                                    Colors.white.withValues(alpha: 0.05),
                                                  ],
                                                )
                                              : null,
                                          color: _currentChapter <= 1
                                              ? Colors.white.withValues(alpha: 0.03)
                                              : null,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.1),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed:
                                              _currentChapter > 1 ? _prevChapter : null,
                                          icon: const Icon(Icons.arrow_back_rounded),
                                          label: const Text('Назад'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor: _currentChapter > 1
                                                ? Colors.white
                                                : Colors.white.withValues(alpha: 0.3),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Chapter counter
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
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
                                          gradient: _currentChapter < _totalChapters
                                              ? const LinearGradient(
                                                  colors: [
                                                    Color(0xFF14FFEC),
                                                    Color(0xFF0D7377),
                                                  ],
                                                )
                                              : null,
                                          color: _currentChapter >= _totalChapters
                                              ? Colors.white.withValues(alpha: 0.03)
                                              : null,
                                          borderRadius: BorderRadius.circular(12),
                                          border: _currentChapter >= _totalChapters
                                              ? Border.all(
                                                  color: Colors.white.withValues(alpha: 0.1),
                                                  width: 1.5,
                                                )
                                              : null,
                                          boxShadow: _currentChapter < _totalChapters
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(0xFF14FFEC)
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 15,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: ElevatedButton.icon(
                                          onPressed: _currentChapter < _totalChapters
                                              ? _nextChapter
                                              : null,
                                          icon: const Icon(Icons.arrow_forward_rounded),
                                          label: const Text('Вперёд'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            foregroundColor:
                                                _currentChapter < _totalChapters
                                                    ? Colors.white
                                                    : Colors.white.withValues(alpha: 0.3),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
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
              colors: [
                const Color(0xFF1A1F3A),
                const Color(0xFF0A0E27),
              ],
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
