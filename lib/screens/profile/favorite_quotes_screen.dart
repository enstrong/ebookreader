import 'package:ebookreader/models/favorite_quote.dart';
import 'package:ebookreader/services/community_service.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:flutter/material.dart';

class FavoriteQuotesScreen extends StatefulWidget {
  final String token;

  const FavoriteQuotesScreen({super.key, required this.token});

  @override
  State<FavoriteQuotesScreen> createState() => _FavoriteQuotesScreenState();
}

class _FavoriteQuotesScreenState extends State<FavoriteQuotesScreen> {
  final CommunityService _communityService = CommunityService();
  List<FavoriteQuote> _quotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuotes();
  }

  Future<void> _loadQuotes() async {
    setState(() => _isLoading = true);
    try {
      final quotes = await _communityService.getMyQuotes(widget.token);
      if (!mounted) return;
      setState(() {
        _quotes = quotes;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка загрузки цитат: $e'),
          backgroundColor: context.palette.danger,
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
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: palette.text),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Любимые цитаты',
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${_quotes.length}',
                      style: TextStyle(
                        color: palette.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: palette.accent),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadQuotes,
                        color: palette.accent,
                        child: _quotes.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(32),
                                children: [
                                  const SizedBox(height: 120),
                                  Icon(
                                    Icons.format_quote_rounded,
                                    color: palette.mutedText,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Опубликованные цитаты появятся здесь.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: palette.mutedText,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  24,
                                ),
                                itemCount: _quotes.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) =>
                                    _QuoteProfileCard(quote: _quotes[index]),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteProfileCard extends StatelessWidget {
  final FavoriteQuote quote;

  const _QuoteProfileCard({required this.quote});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.elevated.withValues(alpha: palette.isDark ? 0.58 : 0.92),
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
          const SizedBox(height: 12),
          Text(
            '${quote.bookTitle} · глава ${quote.chapterOrder}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
