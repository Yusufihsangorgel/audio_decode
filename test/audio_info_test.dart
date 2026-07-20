import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

/// Reads a committed fixture from `test/fixtures/`.
Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

const _fixtures = [
  'sine_44100_mono_1s.ogg',
  'sine_44100_stereo_1s.ogg',
  'sine_48000_mono_halfsec.ogg',
  'sine_44100_mono_1s.mp3',
  'sine_44100_stereo_1s.mp3',
  'sine_48000_mono_halfsec.mp3',
];

void main() {
  group('audioInfo agrees with a full decode', () {
    // The whole point of the API: the geometry it reports without decoding
    // must be exactly what decoding would have told you.
    for (final name in _fixtures) {
      test(name, () {
        final bytes = fixture(name);
        final info = audioInfo(bytes);
        final pcm = decodeAudio(bytes);

        expect(info.sampleRate, pcm.sampleRate, reason: 'sample rate');
        expect(info.channels, pcm.channels, reason: 'channels');
        expect(info.frameCount, pcm.frameCount, reason: 'frame count');
        expect(info.duration, pcm.duration, reason: 'duration');
      });
    }
  });

  test('reports the expected geometry for a known fixture', () {
    final info = audioInfo(fixture('sine_44100_stereo_1s.ogg'));
    expect(info.sampleRate, 44100);
    expect(info.channels, 2);
    // One second of audio, so a frame count around the sample rate.
    expect(info.duration.inMilliseconds, closeTo(1000, 60));
  });

  test('the format-specific entry points match the dispatching one', () {
    final ogg = fixture('sine_44100_mono_1s.ogg');
    final mp3 = fixture('sine_44100_mono_1s.mp3');
    expect(oggInfo(ogg).frameCount, audioInfo(ogg).frameCount);
    expect(mp3Info(mp3).frameCount, audioInfo(mp3).frameCount);
  });

  test('an unrecognized format throws AudioDecodeException', () {
    expect(
      () => audioInfo(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8])),
      throwsA(isA<AudioDecodeException>()),
    );
  });

  test('empty bytes throw ArgumentError', () {
    expect(() => audioInfo(Uint8List(0)), throwsArgumentError);
  });

  test('a truncated Vorbis stream is rejected, not silently reported', () {
    final ogg = fixture('sine_44100_mono_1s.ogg');
    // Keep the signature so detectFormat still says Ogg, but cut the stream.
    final head = Uint8List.sublistView(ogg, 0, 40);
    expect(() => audioInfo(head), throwsA(isA<AudioDecodeException>()));
  });

  test('AudioInfo.duration is zero when the sample rate is', () {
    const info = AudioInfo(sampleRate: 0, channels: 1, frameCount: 100);
    expect(info.duration, Duration.zero);
  });
}
