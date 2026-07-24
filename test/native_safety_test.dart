import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

/// What has to hold for a package decoding untrusted bytes through FFI: bad
/// input becomes a Dart error rather than a crash, decoding does not leak the
/// native buffers it allocates, and the documented truncation behaviour is what
/// actually happens.
void main() {
  group('native safety', () {
    test('undecodable bytes raise, empty input is an argument error', () {
      expect(() => decodeAudio(Uint8List(0)), throwsArgumentError);
      expect(
        () => decodeAudio(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('a truncated Ogg fails, because the container is checksummed', () {
      final ogg = _fixture('sine_44100_mono_1s.ogg');
      expect(
        () => decodeAudio(ogg.sublist(0, 40)),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('a truncated MP3 decodes what arrived, as the README warns', () {
      // MP3 carries no total length, so a cut-off file is indistinguishable
      // from a shorter recording: it decodes the frames present rather than
      // throwing. Callers who may hold a partial download have to check the
      // duration themselves, which is exactly why this is documented.
      final mp3 = _fixture('sine_44100_mono_1s.mp3');
      final whole = decodeAudio(mp3);
      final partial = decodeAudio(mp3.sublist(0, mp3.length ~/ 3));

      expect(partial.frameCount, greaterThan(0));
      expect(partial.frameCount, lessThan(whole.frameCount));
      expect(partial.sampleRate, whole.sampleRate);
    });

    test('repeated decoding does not leak native memory', () {
      final ogg = _fixture('sine_44100_mono_1s.ogg');
      final mp3 = _fixture('sine_44100_mono_1s.mp3');

      // Warm up so first-call allocations are not counted as growth.
      for (var i = 0; i < 20; i++) {
        encodeWav(decodeAudio(ogg));
      }

      // RSS is process-wide, and the test runner runs other files in the same
      // process, so an absolute delta is noisy. A leak has a shape instead: it
      // grows by the same amount every batch. Measure several batches and
      // require at least one late one to be nearly free, which cannot happen
      // if every decode is holding onto its native buffer.
      var previous = ProcessInfo.currentRss;
      final growth = <double>[];
      for (var batch = 0; batch < 4; batch++) {
        for (var i = 0; i < 200; i++) {
          encodeWav(decodeAudio(ogg));
          decodeAudio(mp3);
        }
        final now = ProcessInfo.currentRss;
        growth.add((now - previous) / (1024 * 1024));
        previous = now;
      }

      expect(
        growth.skip(1).any((mb) => mb < 5),
        isTrue,
        reason:
            'growth per 200-cycle batch was $growth; '
            'a leak would keep growing at the same rate',
      );
    });

    test('encodeWav writes a 44-byte header plus the samples', () {
      final pcm = decodeAudio(_fixture('sine_44100_mono_1s.ogg'));
      final wav = encodeWav(pcm);
      expect(wav.length, pcm.samples.length * 2 + 44);
    });

    test('toMono leaves already-mono audio alone', () {
      final pcm = decodeAudio(_fixture('sine_44100_mono_1s.ogg'));
      final mono = pcm.toMono();
      expect(mono.channels, 1);
      expect(mono.frameCount, pcm.frameCount);
    });
  });
}
