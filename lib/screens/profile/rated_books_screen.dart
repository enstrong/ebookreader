import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/screens/book/book_detail_screen.dart';
import 'package:ebookreader/services/user_service.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:flutter/material.dart';

class RatedBooksScreen extends StatefulWidget {
  final String token;

  const RatedBooksScreen({super.key, required this.token});

  @override
  State<RatedBooksScreen> createState() => _RatedBooksScreenState();
}

class _RatedBooksScreenState extends State<RatedBooksScreen> {
  final UserService _userService = UserService();

  List<dynamic> _ratedBooks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRatedBooks();
  }

  Future<void> _loadRatedBooks() async {
    setState(() => _isLoading = true);
    try {
      final ratedBooks = await _userService.getRatedBooks(widget.token);
      if (!mounted) return;
      setState(() {
        _ratedBooks = ratedBooks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки оценённых книг: $e'),
          backgroundColor: context.palette.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: palette.accent,
                          strokeWidth: 2.5,
                        ),
                      )
                    : RefreshIndicator(
                        color: palette.accent,
                        backgroundColor: palette.elevated,
                        onRefresh: _loadRatedBooks,
                        child: _ratedBooks.isEmpty
                            ? _buildEmptyState()
                            : _buildContent(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: palette.text.withValues(
                  alpha: palette.isDark ? 0.08 : 0.12,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.arrow_back, color: palette.text),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Оценённые книги',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: palette.text,
                  ),
                ),
                Text(
                  'История оценок и сигналов рекомендаций',
                  style: TextStyle(fontSize: 14, color: palette.mutedText),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.accent.withValues(alpha: 0.25)),
            ),
            child: Text(
              '${_ratedBooks.length}',
              style: TextStyle(
                color: palette.accent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        _buildSummary(),
        const SizedBox(height: 18),
        ..._ratedBooks.map((book) => _buildRatedBookCard(_asMap(book))),
      ],
    );
  }

  Widget _buildSummary() {
    final ratings = _ratedBooks.map((book) => _ratingOf(_asMap(book))).toList();
    final signals = _ratedBooks
        .map(
          (book) => _asDouble(
            _asMap(book)['recommendationSignal'] ??
                _asMap(book)['recommendationWeight'],
          ),
        )
        .toList();
    final average = ratings.isEmpty
        ? 0.0
        : ratings.reduce((a, b) => a + b) / ratings.length;
    final positiveSignals = signals.where((signal) => signal > 0.05).length;
    final latest = _ratedBooks
        .map((book) => _dateText(_asMap(book)['ratingDate']))
        .firstWhere((date) => date.isNotEmpty, orElse: () => 'нет даты');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          _buildSummaryMetric(
            icon: Icons.star_rate_rounded,
            label: 'Средняя',
            value: average.toStringAsFixed(1),
            color: const Color(0xFFFFD166),
          ),
          _summaryDivider(),
          _buildSummaryMetric(
            icon: Icons.auto_awesome_rounded,
            label: 'Сигналы',
            value: '$positiveSignals',
            color: context.palette.accent,
          ),
          _summaryDivider(),
          _buildSummaryMetric(
            icon: Icons.calendar_month_rounded,
            label: 'Последняя',
            value: latest,
            color: context.palette.secondaryAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final palette = context.palette;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _summaryDivider() {
    return Container(
      width: 1,
      height: 58,
      color: context.palette.border.withValues(alpha: 0.8),
    );
  }

  Widget _buildRatedBookCard(Map<String, dynamic> book) {
    final palette = context.palette;
    final bookId = _asInt(book['id']);
    final title = (book['title'] ?? 'Без названия').toString();
    final author = (book['author'] ?? 'Неизвестный автор').toString();
    final coverUrl = book['coverUrl']?.toString();
    final rating = _ratingOf(book);
    final recommendationSignal = _asDouble(
      book['recommendationSignal'] ?? book['recommendationWeight'],
    );
    final userAverageRating = _asDouble(book['userAverageRating']);
    final ratingDate = _dateText(book['ratingDate'] ?? book['ratedAt']);
    final averageRating = _asDouble(book['averageRating']);
    final ratingsCount = _asInt(book['ratingsCount']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: _panelDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: bookId > 0
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        BookDetailScreen(token: widget.token, bookId: bookId),
                  ),
                ).then((_) => _loadRatedBooks())
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCover(coverUrl, bookId),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildStars(rating),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildInfoChip(
                            Icons.event_available_rounded,
                            ratingDate.isEmpty ? 'Дата неизвестна' : ratingDate,
                          ),
                          _buildInfoChip(
                            Icons.analytics_rounded,
                            _recommendationText(
                              recommendationSignal,
                              userAverageRating,
                            ),
                            color: recommendationSignal > 0.05
                                ? palette.accent
                                : recommendationSignal < -0.05
                                ? palette.danger
                                : palette.mutedText,
                          ),
                          if (averageRating > 0)
                            _buildInfoChip(
                              Icons.groups_rounded,
                              '${averageRating.toStringAsFixed(1)} Goodreads',
                            ),
                          if (ratingsCount > 0)
                            _buildInfoChip(
                              Icons.bar_chart_rounded,
                              _formatCount(ratingsCount),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: palette.mutedText.withValues(alpha: 0.55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(String? coverUrl, int bookId) {
    final palette = context.palette;
    final cover = Container(
      width: 74,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: palette.surface,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: coverUrl == null || coverUrl.isEmpty
            ? _buildPlaceholder()
            : Image.network(
                ApiConstants.getCoverUrl(coverUrl),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildPlaceholder(),
              ),
      ),
    );

    if (bookId <= 0) return cover;
    return Hero(tag: 'book-$bookId', child: cover);
  }

  Widget _buildPlaceholder() {
    final palette = context.palette;
    return Container(
      color: palette.surface,
      child: Icon(
        Icons.menu_book_rounded,
        color: palette.mutedText.withValues(alpha: 0.55),
        size: 34,
      ),
    );
  }

  Widget _buildStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 1; index <= 5; index++)
          Icon(
            index <= rating ? Icons.star_rounded : Icons.star_border_rounded,
            size: 24,
            color: index <= rating
                ? const Color(0xFFFFD166)
                : context.palette.mutedText.withValues(alpha: 0.45),
          ),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text, {Color? color}) {
    final palette = context.palette;
    final chipColor = color ?? palette.secondaryAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text.withValues(alpha: 0.86),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(
          Icons.star_border_rounded,
          color: palette.mutedText.withValues(alpha: 0.4),
          size: 96,
        ),
        const SizedBox(height: 20),
        Text(
          'Пока нет оценённых книг',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.text,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Когда пользователь поставит звёзды книге, она появится здесь вместе с датой и вкладом в рекомендации.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.mutedText,
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  BoxDecoration _panelDecoration() {
    final palette = context.palette;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: LinearGradient(
        colors: [
          palette.text.withValues(alpha: palette.isDark ? 0.05 : 0.16),
          palette.text.withValues(alpha: palette.isDark ? 0.02 : 0.07),
        ],
      ),
      border: Border.all(color: palette.border, width: 1.4),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: palette.isDark ? 0.18 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return {};
  }

  int _ratingOf(Map<String, dynamic> book) {
    return _asInt(book['rating']).clamp(0, 5).toInt();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _recommendationText(double signal, double userAverageRating) {
    if (userAverageRating <= 0) return 'Нет среднего рейтинга';
    final signed = signal >= 0
        ? '+${signal.toStringAsFixed(1)}'
        : signal.toStringAsFixed(1);
    if (signal > 0.75) return 'Сильно выше среднего $signed';
    if (signal > 0.05) return 'Выше среднего $signed';
    if (signal < -0.75) return 'Сильно ниже среднего $signed';
    if (signal < -0.05) return 'Ниже среднего $signed';
    return 'Около среднего';
  }

  String _dateText(dynamic value) {
    if (value == null) return '';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return '';
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M оценок';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K оценок';
    }
    return '$count оценок';
  }
}
