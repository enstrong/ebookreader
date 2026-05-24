import 'dart:async';

import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/screens/admin/add_book_from_file_screen.dart';
import 'package:ebookreader/screens/admin/add_book_screen.dart';
import 'package:ebookreader/screens/admin/manage_chapters_screen.dart';
import 'package:ebookreader/screens/book/book_detail_screen.dart';
import 'package:ebookreader/screens/home/home_screen.dart'
    show FilterScreen, SortDirection, SortOption;
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Экран управления каталогом книг.
///
/// Использует тот же серверный поиск, фильтры, сортировку и постраничную
/// загрузку, что и пользовательский каталог, но оставляет админские действия.
class ManageBooksScreen extends StatefulWidget {
  final String token;

  const ManageBooksScreen({super.key, required this.token});

  @override
  State<ManageBooksScreen> createState() => _ManageBooksScreenState();
}

class _ManageBooksScreenState extends State<ManageBooksScreen>
    with SingleTickerProviderStateMixin {
  final BookService _bookService = BookService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  int _requestSerial = 0;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;

  List<dynamic> _books = [];
  Set<String> _availableGenres = {};
  Set<String> _availableLanguages = {};
  Set<String> _selectedGenres = {};
  Set<String> _selectedLanguages = {};
  Set<String> _selectedContentFeatures = {};
  double? _selectedMinRating;
  SortOption _sortOption = SortOption.popularity;
  SortDirection _sortDirection = SortDirection.descending;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _hasNextPage = false;
  int _currentPage = 0;
  int _totalItems = 0;

  static const int _pageSize = 50;
  static const List<String> _defaultCatalogGenres = [
    'fiction',
    'fantasy, paranormal',
    'young-adult',
    'children',
    'romance',
    'mystery, thriller, crime',
    'history, historical fiction, biography',
    'comics, graphic',
    'poetry',
    'classics',
  ];
  static const Set<String> _defaultCatalogLanguages = {
    'English',
    'Español',
    'العربية',
    'Português',
    'Русский',
    'Қазақша',
  };

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _scrollController.addListener(_onScroll);
    _loadBooks();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks({bool reset = true}) async {
    if (_isLoadingMore || (!reset && !_hasNextPage)) return;
    final requestId = ++_requestSerial;
    setState(() {
      if (reset) {
        _isLoading = true;
        _currentPage = 0;
        _hasNextPage = false;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final page = await _bookService.getAdminBooksPage(
        widget.token,
        page: reset ? 0 : _currentPage + 1,
        size: _pageSize,
        query: _searchQuery,
        languages: _selectedLanguages.map(_languageCode).toList(),
        genres: _selectedGenres.toList(),
        minRating: _selectedMinRating,
        contentFeatures: _selectedContentFeatures,
        sort: _sortQueryValue(),
      );
      final nextBooks = (page['items'] as List? ?? []).cast<dynamic>();

      if (!mounted || requestId != _requestSerial) return;
      setState(() {
        _books = reset ? nextBooks : [..._books, ...nextBooks];
        _availableGenres = {
          ..._defaultCatalogGenres,
          ..._extractGenres(_books),
        };
        _availableLanguages = {
          ..._defaultCatalogLanguages,
          ..._extractLanguages(_books),
        };
        _totalItems = _asInt(page['totalItems']);
        _hasNextPage = page['hasNext'] == true;
        if (!reset && nextBooks.isNotEmpty) {
          _currentPage += 1;
        }
        _isLoading = false;
        _isSearching = false;
        _isLoadingMore = false;
      });
      _animController.forward(from: reset ? 0 : _animController.value);
    } catch (e) {
      if (!mounted || requestId != _requestSerial) return;
      setState(() {
        if (reset) {
          _books = [];
          _totalItems = 0;
        }
        _isLoading = false;
        _isSearching = false;
        _isLoadingMore = false;
      });
      _showSnackBar('Ошибка загрузки книг: $e', isError: true);
    }
  }

  Future<void> _refreshBooks() => _loadBooks(reset: true);

  void _searchBooks(String query) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadBooks(reset: true);
    });
  }

  void _onScroll() {
    if (!_hasNextPage || _isLoading || _isLoadingMore) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 600) {
      _loadBooks(reset: false);
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _languageCode(String label) {
    switch (label.trim().toLowerCase()) {
      case 'english':
      case 'eng':
        return 'eng';
      case 'español':
      case 'spanish':
      case 'spa':
        return 'spa';
      case 'العربية':
      case 'arabic':
      case 'ara':
        return 'ara';
      case 'português':
      case 'portuguese':
      case 'por':
        return 'por';
      case 'русский':
      case 'russian':
      case 'rus':
        return 'rus';
      case 'қазақша':
      case 'kazakh':
      case 'kaz':
        return 'kaz';
      default:
        return label;
    }
  }

  String _languageLabel(String code) {
    final normalized = code.trim().toLowerCase();
    switch (normalized) {
      case 'en':
      case 'eng':
      case 'english':
        return 'English';
      case 'es':
      case 'spa':
      case 'spanish':
      case 'español':
        return 'Español';
      case 'ar':
      case 'ara':
      case 'arabic':
        return 'العربية';
      case 'pt':
      case 'por':
      case 'portuguese':
      case 'português':
        return 'Português';
      case 'ru':
      case 'rus':
      case 'russian':
      case 'русский':
        return 'Русский';
      case 'kk':
      case 'kaz':
      case 'kazakh':
      case 'қазақша':
        return 'Қазақша';
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

  String _sortQueryValue() {
    final suffix = _sortDirection == SortDirection.descending ? 'desc' : 'asc';
    switch (_sortOption) {
      case SortOption.rating:
        return 'rating_$suffix';
      case SortOption.popularity:
        return 'popularity_$suffix';
      case SortOption.language:
        return 'language_$suffix';
      case SortOption.title:
        return 'title_$suffix';
    }
  }

  String _sortLabel() {
    final base = switch (_sortOption) {
      SortOption.rating => 'Рейтинг',
      SortOption.popularity => 'Оценки',
      SortOption.language => 'Язык',
      SortOption.title => 'Название',
    };
    final dir = _sortDirection == SortDirection.descending ? '↓' : '↑';
    return '$base $dir';
  }

  int _activeFilterCount() {
    var count =
        _selectedGenres.length +
        _selectedLanguages.length +
        _selectedContentFeatures.length;
    if (_selectedMinRating != null) count += 1;
    return count;
  }

  Future<void> _openFilterScreen() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => FilterScreen(
          genres: _availableGenres.toList()..sort(),
          selectedGenres: Set.of(_selectedGenres),
          languages: _availableLanguages.toList()..sort(),
          selectedLanguages: Set.of(_selectedLanguages),
          selectedContentFeatures: Set.of(_selectedContentFeatures),
          selectedMinRating: _selectedMinRating,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedGenres = Set.of(result['selectedGenres'] as Set<String>);
        _selectedLanguages = Set.of(result['selectedLanguages'] as Set<String>);
        _selectedContentFeatures = Set.of(
          result['selectedContentFeatures'] as Set<String>,
        );
        _selectedMinRating = result['selectedMinRating'] as double?;
      });
      _loadBooks(reset: true);
    }
  }

  Set<String> _extractGenres(List<dynamic> books) {
    final values = <String>{};
    for (final book in books) {
      final raw = book['genres'] ?? book['genre'];
      if (raw is String) {
        values.addAll(
          raw
              .split(';')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
        );
      } else if (raw is List) {
        values.addAll(
          raw
              .map((item) {
                if (item is String) return item;
                if (item is Map && item.containsKey('name')) {
                  return item['name']?.toString() ?? '';
                }
                return item.toString();
              })
              .where((value) => value.isNotEmpty),
        );
      } else if (raw != null) {
        values.add(raw.toString());
      }
    }
    return values;
  }

  Set<String> _extractLanguages(List<dynamic> books) {
    final values = <String>{};
    for (final book in books) {
      final raw =
          book['language'] ?? book['languageCode'] ?? book['language_code'];
      if (raw != null && raw.toString().trim().isNotEmpty) {
        values.add(_languageLabel(raw.toString()));
      }
    }
    return values;
  }

  Future<void> _deleteBook(int id, String title) async {
    try {
      await _bookService.deleteBook(widget.token, id);
      await _refreshBooks();
      if (mounted) {
        _showSnackBar('Книга "$title" удалена');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Ошибка удаления: $e', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final palette = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? palette.danger : palette.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showDeleteDialog(int id, String title) {
    final palette = context.palette;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.border),
        ),
        title: Text(
          'Удалить книгу?',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Вы уверены, что хотите удалить книгу "$title"?',
          style: TextStyle(color: palette.mutedText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: TextStyle(color: palette.mutedText)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _deleteBook(id, title);
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Удалить'),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openChapters(dynamic book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManageChaptersScreen(
          token: widget.token,
          bookId: book['id'],
          bookTitle: book['title'] ?? 'Без названия',
        ),
      ),
    );
  }

  void _openBookDetail(dynamic book) {
    final bookId = _asInt(book['id']);
    if (bookId <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(token: widget.token, bookId: bookId),
      ),
    ).then((_) => _refreshBooks());
  }

  void _openAddBook() async {
    final added = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddBookScreen(token: widget.token)),
    );
    if (added == true) {
      await _refreshBooks();
      if (mounted) {
        _showSnackBar('Книга успешно добавлена');
      }
    }
  }

  void _openAddBookFromFile() async {
    final added = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddBookFromFileScreen(token: widget.token),
      ),
    );
    if (added == true) {
      await _refreshBooks();
      if (mounted) {
        _showSnackBar('Книга успешно добавлена из файла');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: Container(
        decoration: BoxDecoration(gradient: palette.verticalGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildAddButtons(),
    );
  }

  Widget _buildHeader() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent.withValues(
                    alpha: palette.isDark ? 0.12 : 0.10,
                  ),
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: palette.accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Управление',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Книги • ${_totalItems > 0 ? _totalItems : _books.length}',
                      style: TextStyle(fontSize: 14, color: palette.mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: palette.elevated.withValues(
                alpha: palette.isDark ? 0.18 : 0.82,
              ),
              border: Border.all(color: palette.border),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _searchBooks,
              style: TextStyle(color: palette.text),
              decoration: InputDecoration(
                hintText: 'Поиск книг...',
                hintStyle: TextStyle(color: palette.mutedText),
                prefixIcon: Icon(Icons.search_rounded, color: palette.accent),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: palette.mutedText,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          _searchBooks('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFilterBar(),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final activeFilterCount = _activeFilterCount();
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_totalItems > 0 ? _totalItems : _books.length} результатов • ${_sortLabel()}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.mutedText, fontSize: 13),
          ),
        ),
        IconButton(
          onPressed: _openFilterScreen,
          icon: Badge.count(
            count: activeFilterCount,
            isLabelVisible: activeFilterCount > 0,
            child: const Icon(Icons.filter_list_rounded),
          ),
          color: palette.accent,
          tooltip: 'Фильтры',
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.sort_rounded, color: palette.accent),
          tooltip: 'Сортировать',
          color: palette.elevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: _applySort,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'title_asc', child: Text('Название A → Z')),
            PopupMenuItem(value: 'title_desc', child: Text('Название Z → A')),
            PopupMenuItem(
              value: 'rating_desc',
              child: Text('Рейтинг: высокий → низкий'),
            ),
            PopupMenuItem(
              value: 'rating_asc',
              child: Text('Рейтинг: низкий → высокий'),
            ),
            PopupMenuItem(
              value: 'popularity_desc',
              child: Text('Оценок: высокий → низкий'),
            ),
            PopupMenuItem(
              value: 'popularity_asc',
              child: Text('Оценок: низкий → высокий'),
            ),
            PopupMenuItem(value: 'language_asc', child: Text('Язык A → Z')),
            PopupMenuItem(value: 'language_desc', child: Text('Язык Z → A')),
          ],
        ),
      ],
    );
  }

  void _applySort(String value) {
    setState(() {
      switch (value) {
        case 'title_asc':
          _sortOption = SortOption.title;
          _sortDirection = SortDirection.ascending;
          break;
        case 'title_desc':
          _sortOption = SortOption.title;
          _sortDirection = SortDirection.descending;
          break;
        case 'rating_asc':
          _sortOption = SortOption.rating;
          _sortDirection = SortDirection.ascending;
          break;
        case 'rating_desc':
          _sortOption = SortOption.rating;
          _sortDirection = SortDirection.descending;
          break;
        case 'popularity_asc':
          _sortOption = SortOption.popularity;
          _sortDirection = SortDirection.ascending;
          break;
        case 'popularity_desc':
          _sortOption = SortOption.popularity;
          _sortDirection = SortDirection.descending;
          break;
        case 'language_asc':
          _sortOption = SortOption.language;
          _sortDirection = SortDirection.ascending;
          break;
        case 'language_desc':
          _sortOption = SortOption.language;
          _sortDirection = SortDirection.descending;
          break;
      }
    });
    _loadBooks(reset: true);
  }

  Widget _buildBody() {
    final palette = context.palette;
    if (_isLoading || _isSearching) {
      return Center(child: CircularProgressIndicator(color: palette.accent));
    }
    if (_books.isEmpty) {
      return _buildEmptyState();
    }
    return FadeTransition(
      opacity: _fadeAnimation,
      child: RefreshIndicator(
        onRefresh: _refreshBooks,
        color: palette.accent,
        backgroundColor: palette.surface,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          itemCount: _books.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _books.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: CircularProgressIndicator(
                    color: palette.accent,
                    strokeWidth: 2,
                  ),
                ),
              );
            }
            return _buildBookTile(_books[index], index);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final palette = context.palette;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 80,
            color: palette.mutedText.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 16),
          Text(
            _activeFilterCount() > 0 || _searchQuery.isNotEmpty
                ? 'Книги не найдены'
                : 'Нет книг',
            style: TextStyle(fontSize: 18, color: palette.text),
          ),
          const SizedBox(height: 8),
          Text(
            _activeFilterCount() > 0 || _searchQuery.isNotEmpty
                ? 'Попробуйте изменить фильтры или поиск'
                : 'Добавьте первую книгу',
            style: TextStyle(fontSize: 14, color: palette.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildBookTile(dynamic book, int index) {
    final palette = context.palette;
    final title = book['title'] ?? 'Без названия';
    final author = book['author'] ?? 'Без автора';
    final bookId = _asInt(book['id']);
    final language =
        book['language'] ?? book['languageCode'] ?? book['language_code'];
    final rating = book['averageRating'] ?? book['average_rating'];
    final ratingsCount = book['ratingsCount'] ?? book['ratings_count'];
    final coverUrl = (book['coverUrl'] ?? '').toString();

    return TweenAnimationBuilder(
      duration: Duration(milliseconds: 180 + (index % 10) * 35),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: palette.elevated.withValues(
            alpha: palette.isDark ? 0.18 : 0.9,
          ),
          border: Border.all(color: palette.border, width: 1.2),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          leading: _buildBookCover(coverUrl),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: palette.text,
              fontSize: 16,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.mutedText, fontSize: 13),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (language != null && language.toString().isNotEmpty)
                      _buildTinyTag(_languageLabel(language.toString())),
                    if (rating != null && rating.toString() != '0')
                      _buildTinyTag(
                        '${double.tryParse(rating.toString())?.toStringAsFixed(1) ?? rating} ★',
                      ),
                    if (_asInt(ratingsCount) > 0)
                      _buildTinyTag('${_asInt(ratingsCount)} оценок'),
                  ],
                ),
              ],
            ),
          ),
          onTap: () => _openBookDetail(book),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.list_alt, color: palette.accent),
                onPressed: () => _openChapters(book),
                tooltip: 'Главы',
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: palette.danger),
                onPressed: () => _showDeleteDialog(bookId, title),
                tooltip: 'Удалить',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookCover(String coverUrl) {
    final palette = context.palette;
    return Container(
      width: 50,
      height: 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: palette.surface,
        border: Border.all(color: palette.border),
      ),
      child: coverUrl.isEmpty
          ? Icon(Icons.menu_book, color: palette.accent, size: 26)
          : Image.network(
              ApiConstants.getCoverUrl(coverUrl),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Icon(Icons.menu_book, color: palette.accent, size: 26),
            ),
    );
  }

  Widget _buildTinyTag(String text) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: palette.accent.withValues(alpha: palette.isDark ? 0.11 : 0.09),
      ),
      child: Text(text, style: TextStyle(color: palette.accent, fontSize: 11)),
    );
  }

  Widget _buildAddButtons() {
    final palette = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'add_from_file',
          onPressed: _openAddBookFromFile,
          backgroundColor: palette.secondaryAccent,
          foregroundColor: palette.onAccent,
          elevation: 2,
          tooltip: 'Добавить из EPUB файла',
          child: const Icon(Icons.upload_file),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'add_book',
          onPressed: _openAddBook,
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          icon: const Icon(Icons.add),
          label: const Text(
            'Добавить',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
