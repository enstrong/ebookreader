import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/audio_track.dart';
import 'package:ebookreader/screens/reader/reader_screen.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
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
  final BookmarkService _bookmarkService = BookmarkService();
  final AudioPlayer _player = AudioPlayer(useProxyForRequestHeaders: false);

  List<AudioTrack> _tracks = [];
  int _trackIndex = 0;
  bool _isLoading = true;
  String? _error;
  Duration _lastSavedPosition = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _wasPlaying = false;
  double _playbackSpeed = 1.0;

  AudioTrack? get _currentTrack =>
      _tracks.isEmpty || _trackIndex >= _tracks.length
      ? null
      : _tracks[_trackIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAudioBook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player.dispose();
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

      await _loadCurrentTrack(restorePosition: true);
      _positionSubscription = _player.positionStream.listen(_onPositionChanged);
      _playerStateSubscription = _player.playerStateStream.listen((state) {
        if (_wasPlaying && !state.playing) {
          _saveProgress();
        }
        _wasPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _playNextTrack();
        }
      });

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

  Future<void> _loadCurrentTrack({bool restorePosition = false}) async {
    final track = _currentTrack;
    if (track == null) return;

    final url = ApiConstants.getAudioUrl(track.streamUrl);
    await _player.setUrl(
      url,
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );

    if (restorePosition) {
      final seekTarget = audioResumeTarget(
        trackDurationMs: track.durationMs,
        initialSegmentProgress: widget.initialSegmentProgress,
        initialAudioPositionMs: widget.initialAudioPositionMs,
        initialLastMode: widget.initialLastMode,
      );
      if (seekTarget != null && seekTarget > Duration.zero) {
        await _player.seek(seekTarget);
      }
    }
  }

  Future<void> _playNextTrack() async {
    if (_trackIndex >= _tracks.length - 1) {
      await _saveProgress(segmentProgress: 1.0);
      return;
    }
    await _saveProgress(segmentProgress: 1.0);
    setState(() => _trackIndex++);
    await _loadCurrentTrack();
    await _player.play();
  }

  Future<void> _playPreviousTrack() async {
    if (_trackIndex <= 0) return;
    await _saveProgress();
    setState(() => _trackIndex--);
    await _loadCurrentTrack();
  }

  Future<void> _seekRelative(Duration delta) async {
    final duration = _player.duration;
    final nextPosition = _player.position + delta;
    final bounded = duration == null
        ? (nextPosition < Duration.zero ? Duration.zero : nextPosition)
        : Duration(
            milliseconds: nextPosition.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toInt(),
          );
    await _player.seek(bounded);
    await _saveProgress();
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
          initialSegmentProgress: _segmentProgressFor(track, _player.position),
        ),
      ),
    );
  }

  void _onPositionChanged(Duration position) {
    if ((position - _lastSavedPosition).abs() < const Duration(seconds: 5)) {
      return;
    }
    _lastSavedPosition = position;
    _saveProgress();
  }

  Future<void> _saveProgress({double? segmentProgress}) async {
    final track = _currentTrack;
    if (track == null) return;
    final position = _player.position;
    final progress = segmentProgress ?? _segmentProgressFor(track, position);

    try {
      await _bookmarkService.updateProgress(
        widget.token,
        widget.bookId,
        track.segmentOrder,
        segmentProgress: progress,
        audioPositionMs: position.inMilliseconds,
        lastMode: 'AUDIO',
      );
    } catch (e) {
      debugPrint('Ошибка сохранения прогресса аудио: $e');
    }
  }

  double _segmentProgressFor(AudioTrack track, Duration position) {
    return track.durationMs > 0
        ? (position.inMilliseconds / track.durationMs)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.surface,
        elevation: 0,
        title: Text('Аудиокнига', style: TextStyle(color: palette.text)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: palette.text),
          onPressed: () async {
            await _saveProgress();
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: palette.verticalGradient),
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: palette.accent))
            : _error != null
            ? _buildMessage(_error!)
            : _buildPlayer(),
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

  Widget _buildPlayer() {
    final track = _currentTrack!;
    final palette = context.palette;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Container(
              width: 156,
              height: 156,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: palette.accentGradient,
                boxShadow: [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.20),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: Icon(
                Icons.headphones_rounded,
                size: 80,
                color: palette.onAccent,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ).copyWith(color: palette.text),
            ),
            const SizedBox(height: 8),
            Text(
              widget.author.isEmpty ? 'Неизвестный автор' : widget.author,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.mutedText, fontSize: 15),
            ),
            const SizedBox(height: 28),
            Text(
              '${track.segmentOrder}. ${track.title}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text.withValues(alpha: 0.85),
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 20),
            StreamBuilder<Duration>(
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
                final value = position.inMilliseconds
                    .clamp(0, max.toInt())
                    .toDouble();

                return Column(
                  children: [
                    Slider(
                      value: value,
                      min: 0,
                      max: max,
                      activeColor: palette.accent,
                      inactiveColor: palette.border,
                      onChanged: (nextValue) {
                        _player.seek(Duration(milliseconds: nextValue.round()));
                      },
                      onChangeEnd: (_) => _saveProgress(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(position), style: _timeStyle()),
                        Text(
                          '-${_formatDuration(_remainingDuration(duration, position))}',
                          style: _timeStyle(),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _trackIndex > 0 ? _playPreviousTrack : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                  color: palette.text,
                  disabledColor: palette.mutedText.withValues(alpha: 0.35),
                  iconSize: 42,
                ),
                IconButton(
                  tooltip: 'Назад на 15 секунд',
                  onPressed: () => _seekRelative(const Duration(seconds: -15)),
                  icon: const Icon(Icons.replay_10_rounded),
                  color: palette.text,
                  iconSize: 34,
                ),
                const SizedBox(width: 10),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: palette.accentGradient,
                      ),
                      child: IconButton(
                        onPressed: () async {
                          if (playing) {
                            await _player.pause();
                            await _saveProgress();
                          } else {
                            await _player.play();
                          }
                        },
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        color: palette.onAccent,
                        iconSize: 44,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: 'Вперёд на 15 секунд',
                  onPressed: () => _seekRelative(const Duration(seconds: 15)),
                  icon: const Icon(Icons.forward_10_rounded),
                  color: palette.text,
                  iconSize: 34,
                ),
                IconButton(
                  onPressed: _trackIndex < _tracks.length - 1
                      ? _playNextTrack
                      : null,
                  icon: const Icon(Icons.skip_next_rounded),
                  color: palette.text,
                  disabledColor: palette.mutedText.withValues(alpha: 0.35),
                  iconSize: 42,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _continueReading,
                  icon: const Icon(Icons.menu_book_rounded),
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
                  child: Chip(
                    avatar: const Icon(Icons.speed_rounded, size: 18),
                    label: Text('${_playbackSpeed}x'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Сегмент ${_trackIndex + 1}/${_tracks.length}',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.mutedText, fontSize: 13),
            ),
            const Spacer(),
          ],
        ),
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
