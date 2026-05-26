import 'package:flutter/material.dart';
import 'package:ebookreader/models/community_review.dart';
import 'package:ebookreader/models/favorite_quote.dart';
import 'package:ebookreader/services/community_service.dart';
import 'package:ebookreader/theme/app_theme.dart';

class BookReviewsSection extends StatefulWidget {
  final String token;
  final int bookId;
  final int initialRating;
  final ValueChanged<int> onRatingChanged;

  const BookReviewsSection({
    super.key,
    required this.token,
    required this.bookId,
    required this.initialRating,
    required this.onRatingChanged,
  });

  @override
  State<BookReviewsSection> createState() => _BookReviewsSectionState();
}

class _BookReviewsSectionState extends State<BookReviewsSection> {
  final CommunityService _service = CommunityService();
  final TextEditingController _reviewController = TextEditingController();
  final FocusNode _reviewFocusNode = FocusNode();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  List<CommunityReview> _reviews = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isReplySaving = false;
  bool _isEditingMine = false;
  int? _replyingReviewId;
  int? _replyingParentReplyId;
  int _rating = 0;

  CommunityReview? get _myReview {
    final mine = _reviews.where((review) => review.currentUserReview).toList();
    return mine.isEmpty ? null : mine.first;
  }

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _load();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    _reviewFocusNode.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final reviews = await _service.getReviews(widget.token, widget.bookId);
      if (!mounted) return;
      final mine = reviews.where((review) => review.currentUserReview).toList();
      setState(() {
        _reviews = reviews;
        if (mine.isNotEmpty && !_isEditingMine) {
          _rating = mine.first.rating;
          _reviewController.clear();
        }
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
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      await _service.saveReview(
        token: widget.token,
        bookId: widget.bookId,
        rating: _rating,
        text: text,
      );
      widget.onRatingChanged(_rating);
      _reviewController.clear();
      _isEditingMine = false;
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

  void _startEditingMine(CommunityReview review) {
    setState(() {
      _isEditingMine = true;
      _rating = review.rating;
      _reviewController.text = review.text;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reviewFocusNode.requestFocus();
    });
  }

  void _cancelEditingMine() {
    FocusScope.of(context).unfocus();
    setState(() {
      _isEditingMine = false;
      _reviewController.clear();
      _rating = _myReview?.rating ?? widget.initialRating;
    });
  }

  void _startReply(int reviewId, {int? parentReplyId}) {
    setState(() {
      _replyingReviewId = reviewId;
      _replyingParentReplyId = parentReplyId;
      _replyController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replyFocusNode.requestFocus();
    });
  }

  void _cancelReply() {
    FocusScope.of(context).unfocus();
    setState(() {
      _replyingReviewId = null;
      _replyingParentReplyId = null;
      _replyController.clear();
    });
  }

  Future<void> _saveReply() async {
    final reviewId = _replyingReviewId;
    final text = _replyController.text.trim();
    if (_isReplySaving || reviewId == null || text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _isReplySaving = true);
    try {
      await _service.createReply(
        token: widget.token,
        bookId: widget.bookId,
        reviewId: reviewId,
        parentReplyId: _replyingParentReplyId,
        text: text,
      );
      _replyController.clear();
      _replyingReviewId = null;
      _replyingParentReplyId = null;
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
      if (mounted) setState(() => _isReplySaving = false);
    }
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
    final myReview = _myReview;
    final showComposer = myReview == null || _isEditingMine;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showComposer)
            _ReviewComposer(
              controller: _reviewController,
              focusNode: _reviewFocusNode,
              rating: _rating,
              isSaving: _isSaving,
              isEditing: _isEditingMine,
              onRatingChanged: (rating) => setState(() => _rating = rating),
              onSave: _saveReview,
              onCancel: _isEditingMine ? _cancelEditingMine : null,
            ),
          if (showComposer) const SizedBox(height: 14),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
            )
          else if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  'Пока нет отзывов.',
                  style: TextStyle(color: palette.mutedText),
                ),
              ),
            )
          else
            for (var index = 0; index < _reviews.length; index++) ...[
              _ReviewCard(
                review: _reviews[index],
                onVote: (vote) => _voteReview(_reviews[index], vote),
                onReply: () => _startReply(_reviews[index].id),
                onEdit: _reviews[index].currentUserReview
                    ? () => _startEditingMine(_reviews[index])
                    : null,
                onReplyVote: _voteReply,
                onReplyToReply: (reply) =>
                    _startReply(_reviews[index].id, parentReplyId: reply.id),
              ),
              if (_replyingReviewId == _reviews[index].id) ...[
                const SizedBox(height: 10),
                _ReplyComposer(
                  controller: _replyController,
                  focusNode: _replyFocusNode,
                  isSaving: _isReplySaving,
                  onSave: _saveReply,
                  onCancel: _cancelReply,
                ),
              ],
              if (index != _reviews.length - 1) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _ReplyComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSaving;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _ReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.isSaving,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.newline,
            style: TextStyle(color: palette.text),
            decoration: InputDecoration(
              hintText: 'Ваш ответ',
              hintStyle: TextStyle(color: palette.mutedText),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSaving ? null : onCancel,
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: isSaving ? null : onSave,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Опубликовать'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int rating;
  final bool isSaving;
  final bool isEditing;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSave;
  final VoidCallback? onCancel;

  const _ReviewComposer({
    required this.controller,
    required this.focusNode,
    required this.rating,
    required this.isSaving,
    required this.isEditing,
    required this.onRatingChanged,
    required this.onSave,
    this.onCancel,
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
          Wrap(
            spacing: 2,
            runSpacing: 2,
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
            ],
          ),
          TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 2,
            maxLines: 4,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.newline,
            style: TextStyle(color: palette.text),
            decoration: InputDecoration(
              hintText: 'Напишите отзыв',
              hintStyle: TextStyle(color: palette.mutedText),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onCancel != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: isSaving ? null : onCancel,
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: isSaving ? null : onSave,
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEditing ? 'Сохранить' : 'Опубликовать'),
                ),
              ),
            ],
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
  final VoidCallback? onEdit;
  final ValueChanged<CommunityReply> onReplyToReply;
  final void Function(CommunityReply reply, int vote) onReplyVote;

  const _ReviewCard({
    required this.review,
    required this.onVote,
    required this.onReply,
    required this.onReplyToReply,
    required this.onReplyVote,
    this.onEdit,
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
            onEdit: onEdit,
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
  final VoidCallback? onEdit;

  const _ActionsRow({
    required this.likes,
    required this.dislikes,
    required this.currentVote,
    required this.onVote,
    required this.onReply,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
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
        if (onEdit != null)
          TextButton.icon(
            onPressed: onEdit,
            icon: Icon(Icons.edit_rounded, size: 18, color: palette.mutedText),
            label: Text(
              'Редактировать',
              style: TextStyle(color: palette.mutedText),
            ),
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

class BookQuotesSection extends StatefulWidget {
  final String token;
  final int bookId;

  const BookQuotesSection({
    super.key,
    required this.token,
    required this.bookId,
  });

  @override
  State<BookQuotesSection> createState() => _BookQuotesSectionState();
}

class _BookQuotesSectionState extends State<BookQuotesSection> {
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
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }

    if (_quotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            'Пока нет опубликованных цитат.',
            style: TextStyle(color: palette.mutedText),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var index = 0; index < _quotes.length; index++) ...[
          _QuoteCard(
            quote: _quotes[index],
            onVote: (vote) => _vote(_quotes[index], vote),
          ),
          if (index != _quotes.length - 1) const SizedBox(height: 12),
        ],
      ],
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
              style: TextStyle(color: palette.text, height: 1.45),
            ),
            if (_showDetails) ...[
              const SizedBox(height: 10),
              Text(
                'Глава ${quote.chapterOrder} · опубликовано пользователем ${quote.nickname}',
                style: TextStyle(color: palette.mutedText, fontSize: 12),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 2,
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
