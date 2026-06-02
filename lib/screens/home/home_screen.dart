import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:ebookreader/screens/audio/audio_player_screen.dart';
import 'package:ebookreader/screens/book/book_detail_screen.dart';
import 'package:ebookreader/screens/reader/reader_screen.dart';
import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:ebookreader/utils/book_display.dart';

enum SortOption { title, rating, popularity, language }

enum SortDirection { ascending, descending }

enum LibraryStatusFilter { reading, wantToRead, finished }

/// Экран каталога или пользовательской библиотеки.
///
/// Отображает полный каталог или только импортированные книги с поддержкой поиска
/// по названию и автору. При нажатии на книгу открывается
/// экран детальной информации [BookDetailScreen].
class HomeScreen extends StatefulWidget {
  final String token;
  final bool libraryOnly;
  final String title;
  final String subtitle;

  const HomeScreen({
    super.key,
    required this.token,
    this.libraryOnly = false,
    this.title = 'Каталог',
    this.subtitle = 'Все книги',
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final PageController _libraryPageController = PageController();
  Timer? _searchDebounce;
  int _requestSerial = 0;

  List<dynamic> _books = [];
  List<dynamic> _filteredBooks = [];
  Map<String, dynamic>? _demoAudiobook;
  Set<String> _availableGenres = {};
  Set<String> _availableLanguages = {};
  Set<String> _selectedGenres = {};
  Set<String> _selectedLanguages = {};
  Set<String> _selectedContentFeatures = {};
  double? _selectedMinRating;
  SortOption _sortOption = SortOption.popularity;
  SortDirection _sortDirection = SortDirection.descending;
  String _searchQuery = '';
  LibraryStatusFilter _libraryStatusFilter = LibraryStatusFilter.reading;
  final Set<int> _selectedLibraryBookIds = {};
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isSearchExpanded = false;
  bool _isLoadingMore = false;
  bool _isDeletingLibraryBooks = false;
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
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scrollController.addListener(_onScroll);
    _loadBooks();
  }

  @override
  void dispose() {
    _animController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _libraryPageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token ||
        oldWidget.libraryOnly != widget.libraryOnly) {
      _resetFilters();
      _loadBooks(reset: true);
    }
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
      final cleanBooks = <dynamic>[];
      var totalItems = 0;
      var hasNext = false;

      if (widget.libraryOnly) {
        final books = await _bookmarkService.getBookmarks(
          widget.token,
          limit: _pageSize,
        );
        cleanBooks.addAll(books.cast<dynamic>());
        try {
          _demoAudiobook = await _bookService.getDemoAudiobook(widget.token);
        } catch (e) {
          debugPrint('Ошибка загрузки демо-аудиокниги: $e');
          _demoAudiobook = null;
        }
        totalItems = cleanBooks.length;
      } else {
        final page = await _bookService.getBooksPage(
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
        cleanBooks.addAll((page['items'] as List? ?? []).cast<dynamic>());
        totalItems = _asInt(page['totalItems']);
        hasNext = page['hasNext'] == true;
      }

      if (!mounted || requestId != _requestSerial) {
        return;
      }
      setState(() {
        _books = reset ? cleanBooks : [..._books, ...cleanBooks];
        _filteredBooks = widget.libraryOnly
            ? _filteredLibraryBooks(_books)
            : _books;
        _availableGenres = widget.libraryOnly
            ? _extractGenres(_books)
            : {..._defaultCatalogGenres, ..._extractGenres(_books)};
        _availableLanguages = widget.libraryOnly
            ? _extractLanguages(_books)
            : {
                'English',
                'Español',
                'العربية',
                'Português',
                'Русский',
                'Қазақша',
              };
        _totalItems = totalItems;
        _hasNextPage = widget.libraryOnly ? false : hasNext;
        if (!reset && cleanBooks.isNotEmpty) {
          _currentPage += 1;
        }
        _isLoading = false;
        _isLoadingMore = false;
        _isSearching = false;
      });
      _animController.forward();
    } catch (e) {
      if (!mounted || requestId != _requestSerial) {
        return;
      }
      setState(() {
        if (reset) {
          _books = [];
          _filteredBooks = [];
          _availableGenres = {};
          _availableLanguages = {};
          _totalItems = 0;
        }
        _isLoading = false;
        _isLoadingMore = false;
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Ошибка загрузки книг: $e')),
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

  void _searchBooks(String query) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      _isSearching = query.isNotEmpty;
    });
    if (widget.libraryOnly) {
      setState(() {
        _filteredBooks = _filteredLibraryBooks(_books);
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadBooks(reset: true);
    });
  }

  void _applyLibraryFilters() {
    setState(() {
      _filteredBooks = _filteredLibraryBooks(_books);
    });
  }

  List<dynamic> _filteredLibraryBooks(
    List<dynamic> books, {
    LibraryStatusFilter? statusOverride,
  }) {
    final targetStatus = statusOverride ?? _libraryStatusFilter;
    final query = _searchQuery.trim().toLowerCase();
    final result = books.where((raw) {
      if (raw is! Map<String, dynamic>) return false;
      if (_libraryStatusOf(raw) != targetStatus) return false;
      if (!_passesLocalFilters(raw)) return false;
      if (query.isEmpty) return true;
      final title = (raw['title'] ?? '').toString().toLowerCase();
      final author = (raw['author'] ?? '').toString().toLowerCase();
      return title.contains(query) || author.contains(query);
    }).toList();
    result.sort((a, b) => _compareLibraryBooks(a, b));
    return result;
  }

  bool _passesLocalFilters(Map<String, dynamic> book) {
    if (_selectedLanguages.isNotEmpty &&
        !_selectedLanguages.contains(_bookLanguage(book))) {
      return false;
    }
    if (_selectedGenres.isNotEmpty) {
      final genres = _bookGenres(book).toSet();
      if (!_selectedGenres.any(genres.contains)) return false;
    }
    if (_selectedContentFeatures.isNotEmpty) {
      final availability = _bookAvailability(book);
      if (_selectedContentFeatures.contains('text') &&
          !_hasTextAvailability(availability)) {
        return false;
      }
      if (_selectedContentFeatures.contains('audio') &&
          !_hasAudioAvailability(availability)) {
        return false;
      }
    }
    if (_selectedMinRating != null) {
      final rating =
          double.tryParse(
            (book['average_rating'] ?? book['averageRating'] ?? 0).toString(),
          ) ??
          0.0;
      if (rating < _selectedMinRating!) return false;
    }
    return true;
  }

  int _compareLibraryBooks(dynamic a, dynamic b) {
    if (a is! Map<String, dynamic> || b is! Map<String, dynamic>) return 0;
    int result;
    switch (_sortOption) {
      case SortOption.title:
        result = (a['title'] ?? '').toString().toLowerCase().compareTo(
          (b['title'] ?? '').toString().toLowerCase(),
        );
        break;
      case SortOption.rating:
        result = _bookAverageRating(a).compareTo(_bookAverageRating(b));
        break;
      case SortOption.popularity:
        result = _bookRatingsCount(a).compareTo(_bookRatingsCount(b));
        break;
      case SortOption.language:
        result = _bookLanguage(a).compareTo(_bookLanguage(b));
        break;
    }
    return _sortDirection == SortDirection.ascending ? result : -result;
  }

  double _bookAverageRating(Map<String, dynamic> book) {
    return double.tryParse(
          (book['average_rating'] ?? book['averageRating'] ?? 0).toString(),
        ) ??
        0.0;
  }

  LibraryStatusFilter _libraryStatusOf(Map<String, dynamic> book) {
    final status = (book['status'] ?? 'READING').toString().toUpperCase();
    if (status == 'FINISHED') return LibraryStatusFilter.finished;
    if (status == 'WANT_TO_READ') return LibraryStatusFilter.wantToRead;
    return LibraryStatusFilter.reading;
  }

  int _libraryStatusCount(LibraryStatusFilter status) {
    return _books.where((raw) {
      return raw is Map<String, dynamic> && _libraryStatusOf(raw) == status;
    }).length;
  }

  int _libraryPageIndex(LibraryStatusFilter status) {
    switch (status) {
      case LibraryStatusFilter.reading:
        return 0;
      case LibraryStatusFilter.wantToRead:
        return 1;
      case LibraryStatusFilter.finished:
        return 2;
    }
  }

  LibraryStatusFilter _libraryStatusForPage(int index) {
    switch (index) {
      case 1:
        return LibraryStatusFilter.wantToRead;
      case 2:
        return LibraryStatusFilter.finished;
      case 0:
      default:
        return LibraryStatusFilter.reading;
    }
  }

  void _selectLibraryStatus(LibraryStatusFilter status) {
    if (_libraryStatusFilter == status) return;
    setState(() {
      _libraryStatusFilter = status;
      _filteredBooks = _filteredLibraryBooks(_books);
    });
    if (_libraryPageController.hasClients) {
      _libraryPageController.animateToPage(
        _libraryPageIndex(status),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _toggleLibrarySelection(int bookId) {
    if (!widget.libraryOnly || bookId <= 0) return;
    setState(() {
      if (_selectedLibraryBookIds.contains(bookId)) {
        _selectedLibraryBookIds.remove(bookId);
      } else {
        _selectedLibraryBookIds.add(bookId);
      }
    });
  }

  void _clearLibrarySelection() {
    if (_selectedLibraryBookIds.isEmpty) return;
    setState(_selectedLibraryBookIds.clear);
  }

  Future<void> _deleteSelectedLibraryBooks() async {
    if (_selectedLibraryBookIds.isEmpty || _isDeletingLibraryBooks) return;
    final ids = _selectedLibraryBookIds.toList(growable: false);
    setState(() => _isDeletingLibraryBooks = true);
    try {
      await Future.wait(
        ids.map(
          (bookId) => _bookmarkService.removeFromLibrary(widget.token, bookId),
        ),
      );
      if (!mounted) return;
      setState(() {
        _books.removeWhere((raw) {
          return raw is Map<String, dynamic> && ids.contains(_asInt(raw['id']));
        });
        _selectedLibraryBookIds.clear();
        _filteredBooks = _filteredLibraryBooks(_books);
        _totalItems = _books.length;
        _isDeletingLibraryBooks = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ids.length == 1
                ? 'Книга удалена из библиотеки'
                : 'Книги удалены из библиотеки',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeletingLibraryBooks = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка удаления: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _expandSearch() {
    setState(() => _isSearchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchBooks('');
    if (widget.libraryOnly) {
      setState(() => _isSearchExpanded = false);
    }
    FocusScope.of(context).unfocus();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
    if (widget.libraryOnly && _searchController.text.isEmpty) {
      setState(() => _isSearchExpanded = false);
    }
  }

  void _onScroll() {
    if (widget.libraryOnly || !_hasNextPage || _isLoading || _isLoadingMore) {
      return;
    }
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

  double _asProgress(dynamic value) {
    if (value is num) return value.toDouble().clamp(0.0, 1.0).toDouble();
    return (double.tryParse(value?.toString() ?? '') ?? 0.0)
        .clamp(0.0, 1.0)
        .toDouble();
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

  void _openBookDetail(int bookId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookDetailScreen(token: widget.token, bookId: bookId),
      ),
    ).then((_) {
      if (mounted && widget.libraryOnly) {
        _loadBooks(reset: true);
      }
    });
  }

  Future<void> _openBookPrimaryAction(Map<String, dynamic> book) async {
    final bookId = _asInt(book['id']);
    if (bookId <= 0) return;
    final availability = _bookAvailability(book);
    if (!_hasTextAvailability(availability)) {
      _openBookDetail(bookId);
      return;
    }

    final progress = await _bookmarkService.getProgress(widget.token, bookId);
    final chapters = await _bookService.getBookChapters(widget.token, bookId);
    if (!mounted) return;
    if (chapters.isEmpty) {
      _openBookDetail(bookId);
      return;
    }

    final currentChapter = _asInt(
      progress['segmentOrder'] ?? progress['currentChapter'],
    ).clamp(1, chapters.length).toInt();
    final rawProgress = progress['segmentProgress'];
    final segmentProgress = rawProgress is num
        ? rawProgress.toDouble().clamp(0.0, 1.0).toDouble()
        : double.tryParse(rawProgress?.toString() ?? '')?.clamp(0.0, 1.0) ??
              0.0;
    final rating = _asInt(progress['rating']).clamp(0, 5).toInt();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          token: widget.token,
          bookId: bookId,
          chapterOrder: currentChapter,
          initialSegmentProgress: segmentProgress,
          initialRating: rating,
        ),
      ),
    );
  }

  Future<void> _openDemoAudio(Map<String, dynamic> book) async {
    final bookId = _asInt(book['id']);
    if (bookId <= 0) return;
    final progress = await _bookmarkService.getProgress(widget.token, bookId);
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioPlayerScreen(
          token: widget.token,
          bookId: bookId,
          title: book['title']?.toString() ?? 'The Raven',
          author: authorLabel(book['author']),
          coverUrl: book['coverUrl']?.toString() ?? '',
          initialSegmentOrder: _asInt(
            progress['segmentOrder'] ?? progress['currentChapter'] ?? 1,
          ).clamp(1, 999999).toInt(),
          initialSegmentProgress: _asProgress(progress['segmentProgress']),
          initialAudioPositionMs: _asInt(progress['audioPositionMs']),
          initialLastMode: (progress['lastMode'] ?? 'TEXT').toString(),
        ),
      ),
    ).then((_) => _loadBooks(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: Container(
          decoration: BoxDecoration(gradient: palette.verticalGradient),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  palette.accent.withValues(alpha: 0.2),
                                  palette.secondaryAccent.withValues(
                                    alpha: 0.1,
                                  ),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.auto_stories_rounded,
                              color: palette.accent,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: palette.text,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  '${widget.subtitle} • ${_totalItems > 0 ? _totalItems : _books.length} книг',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: palette.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.libraryOnly && !_isSearchExpanded) ...[
                            const SizedBox(width: 12),
                            _buildSearchIconButton(),
                          ],
                        ],
                      ),
                      if (!widget.libraryOnly || _isSearchExpanded) ...[
                        const SizedBox(height: 18),
                        _buildSearchControl(),
                        const SizedBox(height: 14),
                      ] else
                        const SizedBox(height: 14),
                      _buildFilterBar(),
                    ],
                  ),
                ),

                // Books Grid
                Expanded(
                  child: _isLoading || _isSearching
                      ? Center(
                          child: CircularProgressIndicator(
                            color: palette.accent,
                            strokeWidth: 2.5,
                          ),
                        )
                      : widget.libraryOnly
                      ? _buildLibraryBody()
                      : _filteredBooks.isEmpty
                      ? _buildEmptyState()
                      : _buildBooksGrid(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchControl() {
    final palette = context.palette;
    if (widget.libraryOnly && !_isSearchExpanded) {
      return Align(
        alignment: Alignment.centerRight,
        child: _buildSearchIconButton(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            palette.text.withValues(alpha: palette.isDark ? 0.08 : 0.22),
            palette.text.withValues(alpha: palette.isDark ? 0.04 : 0.10),
          ],
        ),
        border: Border.all(color: palette.border, width: 1.5),
      ),
      child: TextField(
        focusNode: _searchFocusNode,
        controller: _searchController,
        onChanged: _searchBooks,
        onTapOutside: (_) => _dismissKeyboard(),
        style: TextStyle(color: palette.text),
        decoration: InputDecoration(
          hintText: 'Поиск книг...',
          hintStyle: TextStyle(
            color: palette.mutedText.withValues(alpha: 0.75),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: palette.accent.withValues(alpha: 0.7),
          ),
          suffixIcon: _searchController.text.isNotEmpty || widget.libraryOnly
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: palette.mutedText),
                  onPressed: _clearSearch,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchIconButton() {
    final palette = context.palette;
    return Container(
      height: 44,
      width: 44,
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: palette.isDark ? 0.5 : 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, width: 1.2),
      ),
      child: IconButton(
        tooltip: 'Поиск',
        onPressed: _expandSearch,
        icon: Icon(Icons.search_rounded, color: palette.accent),
      ),
    );
  }

  Widget _buildFilterBar() {
    final palette = context.palette;
    final activeFilterCount = _activeFilterCount();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${_totalItems > 0 ? _totalItems : _filteredBooks.length} результатов • ${_sortLabel()}',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(color: palette.mutedText, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: _openFilterScreen,
              icon: Badge.count(
                count: activeFilterCount,
                isLabelVisible: activeFilterCount > 0,
                child: Icon(Icons.filter_list_rounded, color: palette.accent),
              ),
              tooltip: 'Фильтры',
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.sort_rounded, color: palette.accent),
              tooltip: 'Сортировать',
              color: palette.elevated,
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onSelected: (value) {
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
                if (widget.libraryOnly) {
                  _applyLibraryFilters();
                } else {
                  _loadBooks(reset: true);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'title_asc',
                  child: Text(
                    'Название A → Z',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'title_desc',
                  child: Text(
                    'Название Z → A',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'rating_desc',
                  child: Text(
                    'Рейтинг: высокий → низкий',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'rating_asc',
                  child: Text(
                    'Рейтинг: низкий → высокий',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'popularity_desc',
                  child: Text(
                    'Оценок: высокий → низкий',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'popularity_asc',
                  child: Text(
                    'Оценок: низкий → высокий',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'language_asc',
                  child: Text(
                    'Язык A → Z',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
                PopupMenuItem(
                  value: 'language_desc',
                  child: Text(
                    'Язык Z → A',
                    style: TextStyle(color: palette.text, fontSize: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  int _activeFilterCount() {
    var count =
        _selectedLanguages.length +
        _selectedContentFeatures.length +
        _selectedGenres.length;
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
      if (widget.libraryOnly) {
        _applyLibraryFilters();
      } else {
        _loadBooks(reset: true);
      }
    }
  }

  Set<String> _extractGenres(List<dynamic> books) {
    final values = <String>{};
    for (final book in books) {
      values.addAll(_bookGenres(book));
    }
    return values;
  }

  Set<String> _extractLanguages(List<dynamic> books) {
    final values = <String>{};
    for (final book in books) {
      final language = _bookLanguage(book);
      if (language.isNotEmpty) values.add(language);
    }
    return values;
  }

  List<String> _bookGenres(dynamic book) {
    final raw = book['genres'] ?? book['genre'];
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

  String _bookLanguage(dynamic book) {
    final raw =
        book['language'] ?? book['languageCode'] ?? book['language_code'];
    if (raw == null) return '';
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

  String _sortLabel() {
    String base;
    switch (_sortOption) {
      case SortOption.rating:
        base = 'Рейтинг';
        break;
      case SortOption.popularity:
        base = 'Оценки';
        break;
      case SortOption.language:
        base = 'Язык';
        break;
      case SortOption.title:
        base = 'Название';
        break;
    }
    final dir = _sortDirection == SortDirection.descending ? '↓' : '↑';
    return '$base $dir';
  }

  Widget _buildEmptyState() {
    final palette = context.palette;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  palette.text.withValues(alpha: palette.isDark ? 0.05 : 0.15),
                  palette.text.withValues(alpha: palette.isDark ? 0.02 : 0.07),
                ],
              ),
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 80,
              color: palette.mutedText.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.libraryOnly ? 'Библиотека пуста' : 'Книги не найдены',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.libraryOnly
                ? 'Начните читать книгу, и она появится здесь'
                : 'Попробуйте поискать по другому названию или автору',
            style: TextStyle(fontSize: 14, color: palette.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryBody() {
    return Column(
      children: [
        if (_selectedLibraryBookIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildLibrarySelectionBar(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: _buildLibraryStatusTabs(),
        ),
        if (_demoAudiobook != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildDemoAudiobookFeature(_demoAudiobook!),
          ),
        Expanded(
          child: PageView(
            controller: _libraryPageController,
            onPageChanged: (index) {
              final status = _libraryStatusForPage(index);
              setState(() {
                _libraryStatusFilter = status;
                _filteredBooks = _filteredLibraryBooks(_books);
              });
            },
            children: const [
              LibraryStatusFilter.reading,
              LibraryStatusFilter.wantToRead,
              LibraryStatusFilter.finished,
            ].map(_buildLibraryPage).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLibrarySelectionBar() {
    final palette = context.palette;
    final count = _selectedLibraryBookIds.length;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: palette.isDark ? 0.88 : 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Снять выделение',
            onPressed: _isDeletingLibraryBooks ? null : _clearLibrarySelection,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              '$count выбрано',
              style: TextStyle(
                color: palette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _isDeletingLibraryBooks
                ? null
                : _deleteSelectedLibraryBooks,
            icon: _isDeletingLibraryBooks
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.onAccent,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Удалить'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryPage(LibraryStatusFilter status) {
    final books = _filteredLibraryBooks(_books, statusOverride: status);
    return RefreshIndicator(
      color: context.palette.accent,
      onRefresh: () => _loadBooks(reset: true),
      child: books.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.45,
                  child: _buildEmptyState(),
                ),
              ],
            )
          : _buildBooksGrid(books: books),
    );
  }

  Widget _buildLibraryStatusTabs() {
    return Row(
      children: [
        Expanded(
          child: _buildLibraryStatusTab(
            status: LibraryStatusFilter.reading,
            icon: Icons.menu_book_rounded,
            label: 'Читаю',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildLibraryStatusTab(
            status: LibraryStatusFilter.wantToRead,
            icon: Icons.bookmark_border_rounded,
            label: 'Хочу',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildLibraryStatusTab(
            status: LibraryStatusFilter.finished,
            icon: Icons.done_all_rounded,
            label: 'Прочитано',
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryStatusTab({
    required LibraryStatusFilter status,
    required IconData icon,
    required String label,
  }) {
    final palette = context.palette;
    final selected = _libraryStatusFilter == status;
    final count = _libraryStatusCount(status);
    return SizedBox(
      height: 44,
      child: selected
          ? FilledButton.icon(
              onPressed: () {},
              icon: Icon(icon, size: 17),
              label: FittedBox(child: Text('$label $count')),
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.onAccent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: () => _selectLibraryStatus(status),
              icon: Icon(icon, size: 17),
              label: FittedBox(child: Text('$label $count')),
              style: OutlinedButton.styleFrom(
                foregroundColor: palette.mutedText,
                side: BorderSide(color: palette.border),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
    );
  }

  Widget _buildDemoAudiobookFeature(Map<String, dynamic> book) {
    final palette = context.palette;
    final coverUrl = (book['coverUrl'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: palette.isDark ? 0.75 : 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 82,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.border),
            ),
            child: coverUrl.isEmpty
                ? Icon(Icons.graphic_eq_rounded, color: palette.accent)
                : Image.network(
                    ApiConstants.getCoverUrl(coverUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.graphic_eq_rounded, color: palette.accent),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Демо-аудиокнига',
                  style: TextStyle(
                    color: palette.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  book['title']?.toString() ?? 'The Raven',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${authorLabel(book['author'])} · текст + аудио',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.mutedText, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openDemoAudio(book),
                      icon: const Icon(Icons.headphones_rounded, size: 18),
                      label: const Text('Слушать'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openBookPrimaryAction(book),
                      icon: const Icon(Icons.menu_book_rounded, size: 18),
                      label: const Text('Читать'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    _searchController.clear();
    _selectedGenres = {};
    _selectedLanguages = {};
    _selectedContentFeatures = {};
    _selectedMinRating = null;
    _sortOption = SortOption.popularity;
    _sortDirection = SortDirection.descending;
    _searchQuery = '';
    _isSearching = false;
    _isSearchExpanded = false;
    _libraryStatusFilter = LibraryStatusFilter.reading;
    _selectedLibraryBookIds.clear();
  }

  Widget _buildBooksGrid({List<dynamic>? books}) {
    final visibleBooks = books ?? _filteredBooks;
    final useCatalogPaging = books == null && !widget.libraryOnly;
    return GridView.builder(
      controller: useCatalogPaging ? _scrollController : null,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.46,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
      ),
      itemCount:
          visibleBooks.length + (useCatalogPaging && _isLoadingMore ? 2 : 0),
      itemBuilder: (context, index) {
        if (index >= visibleBooks.length) {
          return Center(
            child: CircularProgressIndicator(
              color: context.palette.accent,
              strokeWidth: 2,
            ),
          );
        }
        return TweenAnimationBuilder(
          duration: Duration(milliseconds: 300 + (index * 50)),
          tween: Tween<double>(begin: 0, end: 1),
          builder: (context, double value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value,
                child: _buildBookCard(visibleBooks[index]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBookCard(Map<String, dynamic> book) {
    final palette = context.palette;
    final bookId = _asInt(book['id']);
    final rating = (book['average_rating'] ?? book['averageRating'] ?? 0)
        .toString();
    final ratingsCount = _bookRatingsCount(book);
    final availability = _bookAvailability(book);
    final isSelected = _selectedLibraryBookIds.contains(bookId);

    return GestureDetector(
      onLongPress: widget.libraryOnly
          ? () => _toggleLibrarySelection(bookId)
          : null,
      onTap: () {
        if (widget.libraryOnly && _selectedLibraryBookIds.isNotEmpty) {
          _toggleLibrarySelection(bookId);
          return;
        }
        _openBookDetail(bookId);
      },
      child: Hero(
        tag: 'book-$bookId',
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                palette.elevated.withValues(
                  alpha: palette.isDark ? 0.18 : 0.88,
                ),
                palette.surface.withValues(alpha: palette.isDark ? 0.08 : 0.58),
              ],
            ),
            border: Border.all(
              color: isSelected ? palette.accent : palette.border,
              width: isSelected ? 2.4 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover image
                  Flexible(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        gradient: LinearGradient(
                          colors: [
                            palette.text.withValues(
                              alpha: palette.isDark ? 0.03 : 0.10,
                            ),
                            palette.text.withValues(
                              alpha: palette.isDark ? 0.01 : 0.04,
                            ),
                          ],
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        child:
                            book['coverUrl'] != null &&
                                book['coverUrl'].toString().isNotEmpty
                            ? Image.network(
                                ApiConstants.getCoverUrl(book['coverUrl']),
                                width: double.infinity,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        color: palette.surface.withValues(
                                          alpha: 0.28,
                                        ),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
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
                                    '📍 URL: ${ApiConstants.getCoverUrl(book['coverUrl'])}',
                                  );
                                  return _buildPlaceholder();
                                },
                              )
                            : _buildPlaceholder(),
                      ),
                    ),
                  ),

                  // Book info
                  Flexible(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book['title'] ?? 'Без названия',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: palette.text,
                                    letterSpacing: 0.3,
                                    height: 1.15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  authorLabel(book['author']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.mutedText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildTag(
                                      _availabilityLabel(availability),
                                      color: _availabilityColor(availability),
                                    ),
                                    if (rating != '0')
                                      _buildTag(
                                        '${double.tryParse(rating)?.toStringAsFixed(1) ?? rating} ★',
                                      ),
                                    if (ratingsCount > 0)
                                      _buildTag(
                                        _formatRatingsCount(ratingsCount),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (widget.libraryOnly &&
                                  _selectedLibraryBookIds.isNotEmpty) {
                                _toggleLibrarySelection(bookId);
                                return;
                              }
                              _openBookPrimaryAction(book);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                gradient: _isUsableAvailability(availability)
                                    ? palette.accentGradient
                                    : LinearGradient(
                                        colors: [
                                          palette.text.withValues(alpha: 0.08),
                                          palette.text.withValues(alpha: 0.04),
                                        ],
                                      ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: palette.accent.withValues(
                                      alpha: 0.24,
                                    ),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    color: palette.onAccent,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isUsableAvailability(availability)
                                        ? 'Открыть'
                                        : 'Детали',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: palette.onAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (isSelected)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: palette.onAccent,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _bookRatingsCount(Map<String, dynamic> book) {
    final raw = book['ratings_count'] ?? book['ratingsCount'];
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  String _formatRatingsCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(count >= 10000000 ? 0 : 1)}M оценок';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}K оценок';
    }
    return '$count оценок';
  }

  String _bookAvailability(Map<String, dynamic> book) {
    return (book['availability'] ?? 'METADATA_ONLY').toString();
  }

  bool _isUsableAvailability(String availability) {
    return availability == 'TEXT' ||
        availability == 'AUDIO' ||
        availability == 'SYNCED';
  }

  bool _hasTextAvailability(String availability) {
    return availability == 'TEXT' || availability == 'SYNCED';
  }

  bool _hasAudioAvailability(String availability) {
    return availability == 'AUDIO' || availability == 'SYNCED';
  }

  String _availabilityLabel(String availability) {
    switch (availability) {
      case 'TEXT':
        return 'Текст';
      case 'AUDIO':
        return 'Аудио';
      case 'SYNCED':
        return 'Текст + аудио';
      case 'PDF_ONLY':
        return 'PDF';
      default:
        return 'Каталог';
    }
  }

  Color _availabilityColor(String availability) {
    final palette = context.palette;
    switch (availability) {
      case 'TEXT':
        return palette.accent;
      case 'AUDIO':
        return const Color(0xFFFFD166);
      case 'SYNCED':
        return const Color(0xFF7CFF6B);
      case 'PDF_ONLY':
        return const Color(0xFFFF7A7A);
      default:
        return palette.mutedText;
    }
  }

  Widget _buildTag(String text, {bool selected = false, Color? color}) {
    final palette = context.palette;
    final background = selected
        ? palette.accent
        : color?.withValues(alpha: 0.18) ??
              palette.text.withValues(alpha: palette.isDark ? 0.06 : 0.12);
    final foreground = selected ? palette.onAccent : color ?? palette.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, color: foreground)),
    );
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
          color: palette.mutedText.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class FilterScreen extends StatefulWidget {
  final List<String> genres;
  final Set<String> selectedGenres;
  final List<String> languages;
  final Set<String> selectedLanguages;
  final Set<String> selectedContentFeatures;
  final double? selectedMinRating;

  const FilterScreen({
    super.key,
    required this.genres,
    required this.selectedGenres,
    required this.languages,
    required this.selectedLanguages,
    required this.selectedContentFeatures,
    this.selectedMinRating,
  });

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late Set<String> _selectedGenres;
  late Set<String> _selectedLanguages;
  late Set<String> _selectedContentFeatures;
  double? _selectedMinRating;

  @override
  void initState() {
    super.initState();
    _selectedGenres = Set.of(widget.selectedGenres);
    _selectedLanguages = Set.of(widget.selectedLanguages);
    _selectedContentFeatures = Set.of(widget.selectedContentFeatures);
    _selectedMinRating = widget.selectedMinRating;
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
      case 'kk':
      case 'kaz':
      case 'kazakh':
      case 'қазақша':
        return '🇰🇿';
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

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 0,
        title: Text('Фильтр', style: TextStyle(color: palette.text)),
        actions: [
          TextButton(
            onPressed: _clearFilters,
            child: Text('Сброс', style: TextStyle(color: palette.accent)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Жанр',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ChoiceChip(
                    label: Text(
                      'Все жанры',
                      style: TextStyle(
                        color: _selectedGenres.isEmpty
                            ? palette.onAccent
                            : palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    selected: _selectedGenres.isEmpty,
                    selectedColor: palette.accent,
                    backgroundColor: palette.elevated,
                    side: BorderSide(
                      color: _selectedGenres.isEmpty
                          ? palette.accent
                          : palette.border,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedGenres.clear();
                      });
                    },
                  ),
                  ...widget.genres.map((genre) {
                    final selected = _selectedGenres.contains(genre);
                    return FilterChip(
                      label: Text(
                        genreLabel(genre),
                        style: TextStyle(
                          color: selected ? palette.onAccent : palette.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      selected: selected,
                      selectedColor: palette.accent,
                      backgroundColor: palette.elevated,
                      side: BorderSide(
                        color: selected ? palette.accent : palette.border,
                      ),
                      onSelected: (_) {
                        setState(() {
                          if (selected) {
                            _selectedGenres.remove(genre);
                          } else {
                            _selectedGenres.add(genre);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Доступность',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildContentFeatureChip(
                    feature: 'text',
                    label: 'Есть текст',
                    icon: Icons.menu_book_rounded,
                  ),
                  _buildContentFeatureChip(
                    feature: 'audio',
                    label: 'Есть аудио',
                    icon: Icons.headphones_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Язык',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (widget.languages.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Языки недоступны',
                    style: TextStyle(color: palette.mutedText, fontSize: 14),
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.languages.map((language) {
                    final selected = _selectedLanguages.contains(language);
                    final flag = _languageFlag(language);
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (flag != null) ...[
                            Container(
                              height: 18,
                              width: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? palette.onAccent.withValues(alpha: 0.12)
                                    : palette.text.withValues(alpha: 0.12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                flag,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            _languageLabel(language),
                            style: TextStyle(
                              color: selected ? palette.onAccent : palette.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      selected: selected,
                      selectedColor: palette.accent,
                      backgroundColor: palette.elevated,
                      side: BorderSide(
                        color: selected ? palette.accent : palette.border,
                      ),
                      onSelected: (_) {
                        setState(() {
                          if (selected) {
                            _selectedLanguages.remove(language);
                          } else {
                            _selectedLanguages.add(language);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              const SizedBox(height: 18),
              Text(
                'Рейтинг',
                style: TextStyle(
                  color: palette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildFilterChip(null, 'Все рейтинги'),
                  _buildFilterChip(3.0, '> 3.0'),
                  _buildFilterChip(3.5, '> 3.5'),
                  _buildFilterChip(4.0, '> 4.0'),
                  _buildFilterChip(4.5, '> 4.5'),
                  _buildFilterChip(4.75, '> 4.75'),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _clearFilters,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: palette.border),
                        foregroundColor: palette.text,
                      ),
                      child: const Text('Очистить'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _applyFilters,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.onAccent,
                      ),
                      child: const Text('Применить'),
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

  Widget _buildFilterChip(double? threshold, String label) {
    final palette = context.palette;
    final selected = _selectedMinRating == threshold;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? palette.onAccent : palette.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      selectedColor: palette.accent,
      backgroundColor: palette.elevated,
      side: BorderSide(color: selected ? palette.accent : palette.border),
      onSelected: (_) {
        setState(() {
          _selectedMinRating = selected ? null : threshold;
        });
      },
    );
  }

  Widget _buildContentFeatureChip({
    required String feature,
    required String label,
    required IconData icon,
  }) {
    final palette = context.palette;
    final selected = _selectedContentFeatures.contains(feature);
    return FilterChip(
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? palette.onAccent : palette.accent,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: selected ? palette.onAccent : palette.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      selected: selected,
      selectedColor: palette.accent,
      backgroundColor: palette.elevated,
      side: BorderSide(color: selected ? palette.accent : palette.border),
      onSelected: (_) {
        setState(() {
          if (selected) {
            _selectedContentFeatures.remove(feature);
          } else {
            _selectedContentFeatures.add(feature);
          }
        });
      },
    );
  }

  void _applyFilters() {
    Navigator.of(context).pop({
      'selectedGenres': _selectedGenres,
      'selectedLanguages': _selectedLanguages,
      'selectedContentFeatures': _selectedContentFeatures,
      'selectedMinRating': _selectedMinRating,
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedGenres.clear();
      _selectedLanguages.clear();
      _selectedContentFeatures.clear();
      _selectedMinRating = null;
    });
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
}
