import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/screens/book/book_detail_screen.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:ebookreader/services/recommendation_service.dart';
import 'package:ebookreader/screens/user/user_home.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:ebookreader/utils/book_display.dart';
import 'package:flutter/material.dart';

class RecommendationOnboardingScreen extends StatefulWidget {
  final String token;
  final bool finishToHome;

  const RecommendationOnboardingScreen({
    super.key,
    required this.token,
    this.finishToHome = false,
  });

  @override
  State<RecommendationOnboardingScreen> createState() =>
      _RecommendationOnboardingScreenState();
}

class _RecommendationOnboardingScreenState
    extends State<RecommendationOnboardingScreen> {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();
  final RecommendationService _recommendationService = RecommendationService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _books = [];
  List<dynamic> _preview = [];
  final Map<int, Map<String, dynamic>> _selected = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks({String query = ''}) async {
    setState(() => _isLoading = true);
    try {
      final page = await _bookService.getBooksPage(
        widget.token,
        size: 50,
        query: query,
        sort: 'popular',
      );
      if (!mounted) return;
      setState(() {
        _books = (page['items'] as List? ?? []).cast<dynamic>();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки книг: $e'),
          backgroundColor: context.palette.danger,
        ),
      );
    }
  }

  Future<void> _previewRecommendations() async {
    if (_selected.length < 3) return;
    final interactions = _selected.values
        .map(
          (book) => {
            'goodreadsBookId': book['goodreadsId'] ?? book['goodreads_id'],
            'language': book['language'],
            'rating': 5,
          },
        )
        .toList();
    final payload = await _recommendationService.preview(
      widget.token,
      interactions,
      limit: 10,
    );
    if (!mounted) return;
    setState(() {
      _preview = (payload['recommendations'] as List? ?? []).cast<dynamic>();
    });
  }

  Future<void> _finish() async {
    if (_selected.length < 3 || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      for (final book in _selected.values) {
        await _bookmarkService.updateRating(widget.token, _asInt(book['id']), 5);
      }
      if (!mounted) return;
      if (widget.finishToHome) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => UserHome(token: widget.token)),
          (_) => false,
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка сохранения вкуса: $e'),
          backgroundColor: context.palette.danger,
        ),
      );
    }
  }

  void _toggleBook(Map<String, dynamic> book) {
    final id = _asInt(book['id']);
    if (id == 0) return;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else if (_selected.length < 10) {
        _selected[id] = book;
      }
      _preview = [];
    });
    if (_selected.length >= 3) {
      _previewRecommendations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(gradient: palette.pageGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildSearch(),
              _buildSelectionBar(),
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: palette.accent))
                    : _buildGrid(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _selected.length >= 3 ? _finish : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _selected.length >= 3
                  ? 'Показать рекомендации'
                  : 'Выберите ещё ${3 - _selected.length}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          if (!widget.finishToHome)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_rounded, color: palette.text),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Выберите любимые книги',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'От 3 до 10 книг, рейтинг будет сохранён как 5★',
                  style: TextStyle(color: palette.mutedText, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchController,
        onSubmitted: (value) => _loadBooks(query: value),
        style: TextStyle(color: palette.text),
        decoration: InputDecoration(
          hintText: 'Поиск любимой книги',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            onPressed: () => _loadBooks(query: _searchController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final palette = context.palette;
    final previewTitles = _preview
        .take(3)
        .map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          final book = Map<String, dynamic>.from(row['book'] as Map? ?? {});
          return book['title']?.toString();
        })
        .whereType<String>()
        .join(', ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Выбрано: ${_selected.length}/10',
            style: TextStyle(color: palette.accent, fontWeight: FontWeight.w700),
          ),
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Уже вижу: $previewTitles',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.mutedText, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.52,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _books.length,
      itemBuilder: (context, index) {
        final book = Map<String, dynamic>.from(_books[index] as Map);
        final id = _asInt(book['id']);
        final selected = _selected.containsKey(id);
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BookDetailScreen(token: widget.token, bookId: id),
            ),
          ),
          onTap: () => _toggleBook(book),
          child: Container(
            decoration: BoxDecoration(
              color: context.palette.elevated.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? context.palette.accent : context.palette.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: _cover(book),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book['title']?.toString() ?? 'Без названия',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.palette.text,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        authorLabel(book['author']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.palette.mutedText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _cover(Map<String, dynamic> book) {
    final cover = book['coverUrl']?.toString() ?? '';
    if (cover.isEmpty) {
      return Container(
        color: context.palette.surface,
        child: Icon(Icons.menu_book_rounded, color: context.palette.mutedText),
      );
    }
    return Image.network(
      ApiConstants.getCoverUrl(cover),
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: context.palette.surface,
        child: Icon(Icons.menu_book_rounded, color: context.palette.mutedText),
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
