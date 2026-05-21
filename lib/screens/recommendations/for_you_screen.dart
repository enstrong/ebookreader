import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/screens/book/book_detail_screen.dart';
import 'package:ebookreader/screens/home/home_screen.dart';
import 'package:ebookreader/screens/recommendations/recommendation_onboarding_screen.dart';
import 'package:ebookreader/services/recommendation_service.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:ebookreader/utils/book_display.dart';
import 'package:flutter/material.dart';

class ForYouScreen extends StatefulWidget {
  final String token;

  const ForYouScreen({super.key, required this.token});

  @override
  State<ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<ForYouScreen> {
  final RecommendationService _recommendationService = RecommendationService();
  List<dynamic> _recommendations = [];
  bool _isLoading = true;
  int _sourceCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    setState(() => _isLoading = true);
    try {
      final payload = await _recommendationService.getForYou(
        widget.token,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _recommendations = (payload['recommendations'] as List? ?? [])
            .cast<dynamic>();
        _sourceCount = _asInt(payload['sourceCount']);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки рекомендаций: $e'),
          backgroundColor: context.palette.danger,
        ),
      );
    }
  }

  void _openCatalog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(
          token: widget.token,
          title: 'Каталог',
          subtitle: 'Все книги Goodreads',
        ),
      ),
    );
  }

  Future<void> _openOnboarding() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendationOnboardingScreen(token: widget.token),
      ),
    );
    if (mounted) _loadRecommendations();
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
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: palette.accent),
                      )
                    : RefreshIndicator(
                        color: palette.accent,
                        backgroundColor: palette.elevated,
                        onRefresh: _loadRecommendations,
                        child: _recommendations.isEmpty || _sourceCount < 3
                            ? _buildWarmupState()
                            : _buildRecommendationList(),
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Для вас',
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'AI-рекомендации по вашим оценкам',
                  style: TextStyle(color: palette.mutedText, fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Настроить вкус',
            onPressed: _openOnboarding,
            icon: Icon(Icons.auto_awesome_rounded, color: palette.accent),
          ),
          IconButton(
            tooltip: 'Открыть каталог',
            onPressed: _openCatalog,
            icon: Icon(Icons.search_rounded, color: palette.text),
          ),
        ],
      ),
    );
  }

  Widget _buildWarmupState() {
    final palette = context.palette;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: _panelDecoration(),
          child: Column(
            children: [
              Icon(Icons.psychology_rounded, color: palette.accent, size: 54),
              const SizedBox(height: 16),
              Text(
                'Научим модель вашему вкусу',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Выберите 3-10 книг, которые вам понравились. После этого здесь появится ваша персональная полка.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedText, height: 1.45),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _openOnboarding,
                icon: const Icon(Icons.star_rounded),
                label: const Text('Выбрать любимые книги'),
              ),
              TextButton.icon(
                onPressed: _openCatalog,
                icon: const Icon(Icons.library_books_rounded),
                label: const Text('Открыть полный каталог'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationList() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: _recommendations.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = Map<String, dynamic>.from(_recommendations[index] as Map);
        final book = Map<String, dynamic>.from(item['book'] as Map);
        return _buildRecommendationCard(index + 1, book, item);
      },
    );
  }

  Widget _buildRecommendationCard(
    int rank,
    Map<String, dynamic> book,
    Map<String, dynamic> recommendation,
  ) {
    final palette = context.palette;
    final bookId = _asInt(book['id']);
    final reason = recommendation['reason']?.toString() ?? 'AI match';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BookDetailScreen(token: widget.token, bookId: bookId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: _panelDecoration(),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: palette.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _cover(book, width: 54, height: 78),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['title']?.toString() ?? 'Без названия',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    authorLabel(book['author']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.mutedText, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _chip(reason, palette.accent),
                      _chip('AI ${(100 * _asDouble(recommendation['score'])).toStringAsFixed(0)}%', palette.secondaryAccent),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(Map<String, dynamic> book, {required double width, required double height}) {
    final palette = context.palette;
    final coverUrl = book['coverUrl']?.toString() ?? '';
    if (coverUrl.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: palette.surface,
        child: Icon(Icons.menu_book_rounded, color: palette.mutedText),
      );
    }
    return Image.network(
      ApiConstants.getCoverUrl(coverUrl),
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        width: width,
        height: height,
        color: palette.surface,
        child: Icon(Icons.menu_book_rounded, color: palette.mutedText),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  BoxDecoration _panelDecoration() {
    final palette = context.palette;
    return BoxDecoration(
      color: palette.elevated.withValues(alpha: palette.isDark ? 0.58 : 0.92),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: palette.border),
    );
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
