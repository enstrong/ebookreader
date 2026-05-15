import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/audio_track.dart';
import 'package:ebookreader/services/book_service.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerScreen extends StatefulWidget {
  final String token;
  final int bookId;
  final String title;
  final String author;
  final int initialSegmentOrder;
  final double initialSegmentProgress;
  final int initialAudioPositionMs;

  const AudioPlayerScreen({
    super.key,
    required this.token,
    required this.bookId,
    required this.title,
    required this.author,
    this.initialSegmentOrder = 1,
    this.initialSegmentProgress = 0.0,
    this.initialAudioPositionMs = 0,
  });

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  final BookService _bookService = BookService();
  final BookmarkService _bookmarkService = BookmarkService();
  final AudioPlayer _player = AudioPlayer();

  List<AudioTrack> _tracks = [];
  int _trackIndex = 0;
  bool _isLoading = true;
  String? _error;
  Duration _lastSavedPosition = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  AudioTrack? get _currentTrack =>
      _tracks.isEmpty || _trackIndex >= _tracks.length ? null : _tracks[_trackIndex];

  @override
  void initState() {
    super.initState();
    _loadAudioBook();
  }

  @override
  void dispose() {
    _saveProgress();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadAudioBook() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());

      final tracks = await _bookService.getAudioTracks(widget.token, widget.bookId);
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
    await _player.setUrl(url);

    if (restorePosition) {
      final explicitPosition = widget.initialAudioPositionMs > 0
          ? Duration(milliseconds: widget.initialAudioPositionMs)
          : null;
      final percentPosition = track.durationMs > 0
          ? Duration(
              milliseconds:
                  (track.durationMs * widget.initialSegmentProgress.clamp(0.0, 1.0).toDouble()).round(),
            )
          : null;
      final seekTarget = explicitPosition ?? percentPosition;
      if (seekTarget != null && seekTarget > Duration.zero) {
        await _player.seek(seekTarget);
      }
    }

    await _saveProgress();
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
    final progress = segmentProgress ??
        (track.durationMs > 0
            ? (position.inMilliseconds / track.durationMs).clamp(0.0, 1.0).toDouble()
            : 0.0);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        title: const Text('Аудиокнига', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E27), Color(0xFF1A1F3A)],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF14FFEC)),
              )
            : _error != null
                ? _buildMessage(_error!)
                : _buildPlayer(),
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 16,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    final track = _currentTrack!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.25),
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: const Icon(Icons.headphones_rounded, size: 92, color: Colors.white),
            ),
            const SizedBox(height: 32),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.author.isEmpty ? 'Неизвестный автор' : widget.author,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 15),
            ),
            const SizedBox(height: 28),
            Text(
              '${track.segmentOrder}. ${track.title}',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 17),
            ),
            const SizedBox(height: 20),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = _player.duration ??
                    (track.durationMs > 0 ? Duration(milliseconds: track.durationMs) : Duration.zero);
                final max = duration.inMilliseconds <= 0
                    ? 1.0
                    : duration.inMilliseconds.toDouble();
                final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

                return Column(
                  children: [
                    Slider(
                      value: value,
                      min: 0,
                      max: max,
                      activeColor: const Color(0xFF14FFEC),
                      inactiveColor: Colors.white.withValues(alpha: 0.12),
                      onChanged: (nextValue) {
                        _player.seek(Duration(milliseconds: nextValue.round()));
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_formatDuration(position), style: _timeStyle()),
                        Text(_formatDuration(duration), style: _timeStyle()),
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
                  color: Colors.white,
                  disabledColor: Colors.white.withValues(alpha: 0.25),
                  iconSize: 42,
                ),
                const SizedBox(width: 18),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF14FFEC), Color(0xFF0D7377)],
                        ),
                      ),
                      child: IconButton(
                        onPressed: () => playing ? _player.pause() : _player.play(),
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: Colors.white,
                        iconSize: 44,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 18),
                IconButton(
                  onPressed: _trackIndex < _tracks.length - 1 ? _playNextTrack : null,
                  icon: const Icon(Icons.skip_next_rounded),
                  color: Colors.white,
                  disabledColor: Colors.white.withValues(alpha: 0.25),
                  iconSize: 42,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              '${_trackIndex + 1}/${_tracks.length}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  TextStyle _timeStyle() {
    return TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12);
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
}
