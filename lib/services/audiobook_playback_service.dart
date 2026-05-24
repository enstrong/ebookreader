import 'dart:async';

import 'package:ebookreader/constants/api_constants.dart';
import 'package:ebookreader/models/audio_track.dart';
import 'package:ebookreader/services/bookmark_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class AudiobookPlaybackService {
  AudiobookPlaybackService._();

  static final AudiobookPlaybackService instance = AudiobookPlaybackService._();

  final AudioPlayer player = AudioPlayer(useProxyForRequestHeaders: false);
  final BookmarkService _bookmarkService = BookmarkService();
  final ValueNotifier<int> trackIndexNotifier = ValueNotifier<int>(0);

  List<AudioTrack> tracks = [];
  String _token = '';
  int _bookId = 0;
  String _title = '';
  String _author = '';
  String _coverUrl = '';
  Duration _lastSavedPosition = Duration.zero;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _wasPlaying = false;

  int get bookId => _bookId;
  int get trackIndex => trackIndexNotifier.value;
  AudioTrack? get currentTrack =>
      tracks.isEmpty || trackIndex >= tracks.length ? null : tracks[trackIndex];

  Future<void> load({
    required String token,
    required int bookId,
    required String title,
    required String author,
    required String coverUrl,
    required List<AudioTrack> tracks,
    required int initialSegmentOrder,
    required double initialSegmentProgress,
    required int initialAudioPositionMs,
    required String initialLastMode,
  }) async {
    final wasSameBook = _bookId == bookId;
    _token = token;
    _bookId = bookId;
    _title = title;
    _author = author;
    _coverUrl = coverUrl;
    this.tracks = tracks;
    _bindSubscriptions();

    final desiredIndex = tracks.indexWhere(
      (track) => track.segmentOrder == initialSegmentOrder,
    );
    final nextIndex = desiredIndex >= 0 ? desiredIndex : 0;
    final shouldReuseCurrentAudio =
        player.audioSource != null &&
        wasSameBook &&
        initialLastMode.toUpperCase() == 'AUDIO';

    if (shouldReuseCurrentAudio) {
      trackIndexNotifier.value = trackIndex.clamp(0, tracks.length - 1).toInt();
      return;
    }

    trackIndexNotifier.value = nextIndex;
    await _loadCurrentTrack(
      restorePosition: true,
      initialSegmentProgress: initialSegmentProgress,
      initialAudioPositionMs: initialAudioPositionMs,
      initialLastMode: initialLastMode,
    );
  }

  Future<void> playNextTrack() async {
    if (trackIndex >= tracks.length - 1) {
      await saveProgress(segmentProgress: 1.0);
      return;
    }
    await saveProgress(segmentProgress: 1.0);
    trackIndexNotifier.value++;
    await _loadCurrentTrack();
    await player.play();
  }

  Future<void> playPreviousTrack() async {
    if (trackIndex <= 0) return;
    await saveProgress();
    trackIndexNotifier.value--;
    await _loadCurrentTrack();
  }

  Future<void> seekRelative(Duration delta) async {
    final duration = player.duration;
    final nextPosition = player.position + delta;
    final bounded = duration == null
        ? (nextPosition < Duration.zero ? Duration.zero : nextPosition)
        : Duration(
            milliseconds: nextPosition.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toInt(),
          );
    await player.seek(bounded);
    await saveProgress();
  }

  Future<void> saveProgress({double? segmentProgress}) async {
    final track = currentTrack;
    if (track == null || _token.isEmpty || _bookId <= 0) return;
    final position = player.position;
    final progress = segmentProgress ?? _segmentProgressFor(track, position);

    try {
      await _bookmarkService.updateProgress(
        _token,
        _bookId,
        track.segmentOrder,
        segmentProgress: progress,
        audioPositionMs: position.inMilliseconds,
        lastMode: 'AUDIO',
      );
    } catch (e) {
      debugPrint('Ошибка сохранения прогресса аудио: $e');
    }
  }

  double segmentProgressForCurrentTrack() {
    final track = currentTrack;
    if (track == null) return 0.0;
    return _segmentProgressFor(track, player.position);
  }

  Future<void> _loadCurrentTrack({
    bool restorePosition = false,
    double initialSegmentProgress = 0.0,
    int initialAudioPositionMs = 0,
    String initialLastMode = 'TEXT',
  }) async {
    final track = currentTrack;
    if (track == null) return;

    final streamUrl = ApiConstants.getAudioUrl(track.streamUrl);
    final cover = _coverArtUri();
    final source = AudioSource.uri(
      Uri.parse(streamUrl),
      headers: {'Authorization': 'Bearer $_token'},
      tag: MediaItem(
        id: 'book-$_bookId-track-${track.id}',
        album: _title,
        title: track.title.isEmpty ? _title : track.title,
        artist: _author.isEmpty ? 'Неизвестный автор' : _author,
        artUri: cover,
        duration: track.durationMs > 0
            ? Duration(milliseconds: track.durationMs)
            : null,
      ),
    );

    await player.setAudioSource(source);

    if (restorePosition) {
      final seekTarget = _audioResumeTarget(
        trackDurationMs: track.durationMs,
        initialSegmentProgress: initialSegmentProgress,
        initialAudioPositionMs: initialAudioPositionMs,
        initialLastMode: initialLastMode,
      );
      if (seekTarget != null && seekTarget > Duration.zero) {
        await player.seek(seekTarget);
      }
    }
  }

  void _bindSubscriptions() {
    _positionSubscription ??= player.positionStream.listen((position) {
      if ((position - _lastSavedPosition).abs() < const Duration(seconds: 5)) {
        return;
      }
      _lastSavedPosition = position;
      saveProgress();
    });

    _playerStateSubscription ??= player.playerStateStream.listen((state) {
      if (_wasPlaying && !state.playing) {
        saveProgress();
      }
      _wasPlaying = state.playing;
      if (state.processingState == ProcessingState.completed) {
        playNextTrack();
      }
    });
  }

  Uri? _coverArtUri() {
    final raw = _coverUrl.trim();
    if (raw.isEmpty) return null;
    return Uri.tryParse(ApiConstants.getCoverUrl(raw));
  }

  double _segmentProgressFor(AudioTrack track, Duration position) {
    return track.durationMs > 0
        ? (position.inMilliseconds / track.durationMs)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;
  }

  Duration? _audioResumeTarget({
    required int trackDurationMs,
    required double initialSegmentProgress,
    required int initialAudioPositionMs,
    required String initialLastMode,
  }) {
    if (initialLastMode.toUpperCase() == 'AUDIO' &&
        initialAudioPositionMs > 0) {
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
}
