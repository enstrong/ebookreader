import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audio_session/audio_session.dart';
import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/audio_track.dart';
import 'package:ebookreader/screens/reader/reader_screen.dart';
import 'package:ebookreader/services/audiobook_playback_service.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

Duration? audioResumeTarget({
  required int trackDurationMs,
  required double initialSegmentProgress,
  required int initialAudioPositionMs,
  required String initialLastMode,
}) {
  if (initialLastMode.toUpperCase() == 'AUDIO' && initialAudioPositionMs > 0) {
    return Duration(milliseconds: initialAudioPositionMs);
  }
  if (trackDurationMs <= 0) {
    return null;
  }
  return Duration(
    milliseconds: (trackDurationMs * initialSegmentProgress.clamp(0.0, 1.0))
        .round(),
  );
}

class AudioPlayerScreen extends StatefulWidget {
  final String token;
  final int bookId;
  final String title;
  final String author;
  final String coverUrl;
  final int initialSegmentOrder;
  final double initialSegmentProgress;
  final int initialAudioPositionMs;
  final String initialLastMode;

  const AudioPlayerScreen({
    super.key,
    required this.token,
    required this.bookId,
    required this.title,
    required this.author,
    this.coverUrl = '',
    this.initialSegmentOrder = 1,
    this.initialSegmentProgress = 0.0,
    this.initialAudioPositionMs = 0,
    this.initialLastMode = 'TEXT',
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen>
    with WidgetsBindingObserver {
  final BookService _bookService = BookService();
  final AudiobookPlaybackService _playback = AudiobookPlaybackService.instance;

  List<AudioTrack> _tracks = [];
  int _trackIndex = 0;
  bool _isLoading = true;
  String? _error;
  double _playbackSpeed = 1.0;

  AudioPlayer get _player => _playback.player;

  AudioTrack? get _currentTrack =>
      _tracks.isEmpty || _trackIndex >= _tracks.length
      ? null
      : _tracks[_trackIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback.trackIndexNotifier.addListener(_syncTrackIndex);
    _loadAudioBook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback.trackIndexNotifier.removeListener(_syncTrackIndex);
    _saveProgress();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveProgress();
    }
  }

  Future<void> _loadAudioBook() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());

      final tracks = await _bookService.getAudioTracks(
        widget.token,
        widget.bookId,
      );
      if (tracks.isEmpty) {
        setState(() {
          _tracks = [];
          _isLoading = false;
          _error = 'Для этой книги пока нет аудиотреков';
        });
        return;
      }

      final initialIndex = tracks.indexWhere(
        (track) => track.segmentOrder == widget.initialSegmentOrder,
      );
      _tracks = tracks;
      _trackIndex = initialIndex >= 0 ? initialIndex : 0;

      await _playback.load(
        token: widget.token,
        bookId: widget.bookId,
        title: widget.title,
        author: widget.author,
        coverUrl: widget.coverUrl,
        tracks: tracks,
        initialSegmentOrder: widget.initialSegmentOrder,
        initialSegmentProgress: widget.initialSegmentProgress,
        initialAudioPositionMs: widget.initialAudioPositionMs,
        initialLastMode: widget.initialLastMode,
      );
      _trackIndex = _playback.trackIndex;
      _playbackSpeed = _player.speed;

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Ошибка загрузки аудио: $e';
        });
      }
    }
  }

  Future<void> _playNextTrack() async {
    await _playback.playNextTrack();
    if (mounted) setState(() => _trackIndex = _playback.trackIndex);
  }

  Future<void> _playPreviousTrack() async {
    await _playback.playPreviousTrack();
    if (mounted) setState(() => _trackIndex = _playback.trackIndex);
  }

  Future<void> _seekRelative(Duration delta) async {
    await _playback.seekRelative(delta);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    await _player.setSpeed(speed);
    if (mounted) {
      setState(() => _playbackSpeed = speed);
    }
  }

  Future<void> _continueReading() async {
    final track = _currentTrack;
    if (track == null) return;
    await _saveProgress();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          token: widget.token,
          bookId: widget.bookId,
          chapterOrder: track.segmentOrder,
          initialSegmentProgress: _playback.segmentProgressForCurrentTrack(),
        ),
      ),
    );
  }

  void _syncTrackIndex() {
    if (!mounted) return;
    final nextIndex = _playback.trackIndex;
    if (nextIndex != _trackIndex) {
      setState(() => _trackIndex = nextIndex);
    }
  }

  Future<void> _saveProgress({double? segmentProgress}) async {
    await _playback.saveProgress(segmentProgress: segmentProgress);
  }

  String get _resolvedCoverUrl {
    final raw = widget.coverUrl.trim();
    if (raw.isEmpty) return '';
    return ApiConstants.getCoverUrl(raw);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final coverUrl = _resolvedCoverUrl;
    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Аудиокнига',
          style: TextStyle(
            color: palette.text,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: palette.text),
          onPressed: () async {
            await _saveProgress();
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
      body: Stack(
        children: [
          _buildBackdrop(palette, coverUrl),
          _isLoading
              ? Center(child: CircularProgressIndicator(color: palette.accent))
              : _error != null
              ? _buildMessage(_error!)
              : _buildPlayer(coverUrl),
        ],
      ),
    );
  }

  Widget _buildMessage(String message) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.text.withValues(alpha: 0.75),
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBackdrop(AppPalette palette, String coverUrl) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(gradient: palette.pageGradient),
          ),
          if (coverUrl.isNotEmpty)
            Opacity(
              opacity: palette.isDark ? 0.38 : 0.24,
              child: Transform.scale(
                scale: 1.12,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                  child: Image.network(
                    coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.background.withValues(
                    alpha: palette.isDark ? 0.28 : 0.42,
                  ),
                  palette.background.withValues(
                    alpha: palette.isDark ? 0.78 : 0.84,
                  ),
                  palette.surface.withValues(
                    alpha: palette.isDark ? 0.96 : 0.92,
                  ),
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverArt(double size, String coverUrl) {
    final palette = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.42 : 0.18),
            blurRadius: 36,
            offset: const Offset(0, 22),
          ),
          BoxShadow(
            color: palette.accent.withValues(
              alpha: palette.isDark ? 0.16 : 0.10,
            ),
            blurRadius: 42,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: coverUrl.isEmpty
          ? _buildCoverFallback(size)
          : Image.network(
              coverUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return _buildCoverFallback(size, isLoading: true);
              },
              errorBuilder: (context, error, stackTrace) =>
                  _buildCoverFallback(size),
            ),
    );
  }

  Widget _buildCoverFallback(double size, {bool isLoading = false}) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: palette.accentGradient),
      child: Center(
        child: isLoading
            ? CircularProgressIndicator(
                color: palette.onAccent,
                strokeWidth: 2.8,
              )
            : Icon(
                Icons.menu_book_rounded,
                color: palette.onAccent,
                size: math.max(52, size * 0.30),
              ),
      ),
    );
  }

  Widget _buildSegmentInfo(AudioTrack track) {
    final palette = context.palette;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: palette.elevated.withValues(
              alpha: palette.isDark ? 0.42 : 0.62,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            'Сегмент ${_trackIndex + 1}/${_tracks.length}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${track.segmentOrder}. ${track.title}',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.text.withValues(alpha: 0.88),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(AudioTrack track) {
    final palette = context.palette;
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration =
            _player.duration ??
            (track.durationMs > 0
                ? Duration(milliseconds: track.durationMs)
                : Duration.zero);
        final max = duration.inMilliseconds <= 0
            ? 1.0
            : duration.inMilliseconds.toDouble();
        final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                activeTrackColor: palette.text,
                inactiveTrackColor: palette.text.withValues(alpha: 0.16),
                thumbColor: palette.text,
                overlayColor: palette.text.withValues(alpha: 0.10),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              ),
              child: Slider(
                value: value,
                min: 0,
                max: max,
                onChanged: (nextValue) {
                  _player.seek(Duration(milliseconds: nextValue.round()));
                },
                onChangeEnd: (_) => _saveProgress(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: _timeStyle()),
                  Text(
                    '-${_formatDuration(_remainingDuration(duration, position))}',
                    style: _timeStyle(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControls() {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _roundControl(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Предыдущий сегмент',
          onPressed: _trackIndex > 0 ? _playPreviousTrack : null,
          size: 48,
          iconSize: 32,
        ),
        const SizedBox(width: 8),
        _roundControl(
          icon: Icons.replay_10_rounded,
          tooltip: 'Назад на 15 секунд',
          onPressed: () => _seekRelative(const Duration(seconds: -15)),
          size: 52,
          iconSize: 31,
        ),
        const SizedBox(width: 14),
        StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            final isBuffering =
                snapshot.data?.processingState == ProcessingState.buffering ||
                snapshot.data?.processingState == ProcessingState.loading;
            return Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.text,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: palette.isDark ? 0.32 : 0.14,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: IconButton(
                tooltip: playing ? 'Пауза' : 'Слушать',
                onPressed: isBuffering
                    ? null
                    : () async {
                        if (playing) {
                          await _player.pause();
                          await _saveProgress();
                        } else {
                          await _player.play();
                        }
                      },
                icon: isBuffering
                    ? SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: palette.background,
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                color: palette.background,
                iconSize: 50,
              ),
            );
          },
        ),
        const SizedBox(width: 14),
        _roundControl(
          icon: Icons.forward_10_rounded,
          tooltip: 'Вперёд на 15 секунд',
          onPressed: () => _seekRelative(const Duration(seconds: 15)),
          size: 52,
          iconSize: 31,
        ),
        const SizedBox(width: 8),
        _roundControl(
          icon: Icons.skip_next_rounded,
          tooltip: 'Следующий сегмент',
          onPressed: _trackIndex < _tracks.length - 1 ? _playNextTrack : null,
          size: 48,
          iconSize: 32,
        ),
      ],
    );
  }

  Widget _roundControl({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    required double size,
    required double iconSize,
  }) {
    final palette = context.palette;
    final enabled = onPressed != null;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: palette.elevated.withValues(
            alpha: enabled ? (palette.isDark ? 0.34 : 0.56) : 0.14,
          ),
          foregroundColor: palette.text,
          disabledForegroundColor: palette.mutedText.withValues(alpha: 0.35),
          shape: const CircleBorder(),
        ),
        icon: Icon(icon),
        iconSize: iconSize,
      ),
    );
  }

  Widget _buildUtilityRow() {
    final palette = context.palette;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: _continueReading,
          style: FilledButton.styleFrom(
            backgroundColor: palette.text,
            foregroundColor: palette.background,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          icon: const Icon(Icons.menu_book_rounded, size: 19),
          label: const Text('Продолжить читать'),
        ),
        PopupMenuButton<double>(
          tooltip: 'Скорость',
          initialValue: _playbackSpeed,
          onSelected: _setPlaybackSpeed,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 0.75, child: Text('0.75x')),
            PopupMenuItem(value: 1.0, child: Text('1x')),
            PopupMenuItem(value: 1.25, child: Text('1.25x')),
            PopupMenuItem(value: 1.5, child: Text('1.5x')),
            PopupMenuItem(value: 2.0, child: Text('2x')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: palette.elevated.withValues(
                alpha: palette.isDark ? 0.34 : 0.58,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed_rounded, size: 18, color: palette.text),
                const SizedBox(width: 7),
                Text(
                  '${_playbackSpeed}x',
                  style: TextStyle(
                    color: palette.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayer(String coverUrl) {
    final track = _currentTrack!;
    final palette = context.palette;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 720;
          final horizontalPadding = constraints.maxWidth < 380 ? 20.0 : 28.0;
          final coverSize = math.min(
            constraints.maxWidth - horizontalPadding * 2,
            compact
                ? constraints.maxHeight * 0.32
                : constraints.maxHeight * 0.40,
          );

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  compact ? 18 : 28,
                  horizontalPadding,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Сейчас играет',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: compact ? 16 : 24),
                        Center(child: _buildCoverArt(coverSize, coverUrl)),
                        SizedBox(height: compact ? 22 : 30),
                        Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: compact ? 24 : 28,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.author.isEmpty
                              ? 'Неизвестный автор'
                              : widget.author,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: compact ? 18 : 24),
                        _buildSegmentInfo(track),
                      ],
                    ),
                    SizedBox(height: compact ? 18 : 26),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildProgress(track),
                        SizedBox(height: compact ? 18 : 26),
                        _buildControls(),
                        SizedBox(height: compact ? 18 : 22),
                        _buildUtilityRow(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  TextStyle _timeStyle() {
    return TextStyle(color: context.palette.mutedText, fontSize: 12);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Duration _remainingDuration(Duration duration, Duration position) {
    final remaining = duration - position;
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
