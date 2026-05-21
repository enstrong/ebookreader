import 'package:ebookreader/screens/audio/audio_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio resume uses saved timestamp after audio progress', () {
    final target = audioResumeTarget(
      trackDurationMs: 100000,
      initialSegmentProgress: 0.25,
      initialAudioPositionMs: 45000,
      initialLastMode: 'AUDIO',
    );

    expect(target, const Duration(milliseconds: 45000));
  });

  test('audio resume uses text percentage after text progress', () {
    final target = audioResumeTarget(
      trackDurationMs: 100000,
      initialSegmentProgress: 0.25,
      initialAudioPositionMs: 45000,
      initialLastMode: 'TEXT',
    );

    expect(target, const Duration(milliseconds: 25000));
  });
}
