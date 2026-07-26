import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// What a truncated file actually does.
///
/// The README used to say that a truncated Ogg "fails with exceptions"
/// because of the per-page checksums. Measured across a sweep of truncation
/// points, that is only true while the cut lands in the header. Once the
/// header is intact the decoder returns whatever it managed to read, and at
/// one particular cut it returned success with zero frames, which is the worst
/// outcome available: a caller validating an upload would accept a file that
/// produced no audio at all.
void main() {
  group('truncated input', () {
    final ogg = fixture('sine_44100_stereo_1s.ogg');

    test('a cut inside the header is rejected', () {
      for (final percent in [10, 25]) {
        final cut = Uint8List.sublistView(ogg, 0, ogg.length * percent ~/ 100);
        expect(
          () => decodeOgg(cut),
          throwsA(isA<AudioDecodeException>()),
          reason: 'header truncated at $percent% should not decode',
        );
      }
    });

    test('a decode that yields no frames is an error, not an empty result', () {
      // The regression this file exists for. Before the guard, some cut points
      // returned a PcmAudio with frameCount 0 and no exception. Sweeping is
      // deliberate: which byte offset produces the empty decode depends on
      // where the page boundaries fall, so pinning one percentage would make
      // this test pass for the wrong reason on a different fixture.
      for (var percent = 5; percent < 100; percent += 5) {
        final cut = Uint8List.sublistView(ogg, 0, ogg.length * percent ~/ 100);
        try {
          final pcm = decodeOgg(cut);
          expect(
            pcm.frameCount,
            greaterThan(0),
            reason: 'decodeOgg returned success with no audio at $percent%',
          );
          expect(pcm.channels, greaterThan(0));
          expect(pcm.sampleRate, greaterThan(0));
        } on AudioDecodeException {
          // Rejecting a truncated stream is fine. Accepting it silently and
          // handing back nothing is not.
        }
      }
    });

    test('a cut past the header still decodes the audio it did receive', () {
      // Documented behaviour rather than aspiration: stb_vorbis is a pull
      // decoder and stops when the data runs out. Detecting that the stream
      // ended early needs the end-of-stream page flag, which this package does
      // not check yet. The README says so.
      final cut = Uint8List.sublistView(ogg, 0, ogg.length * 75 ~/ 100);
      final pcm = decodeOgg(cut);
      expect(pcm.frameCount, greaterThan(0));
      expect(pcm.frameCount, lessThan(decodeOgg(ogg).frameCount));
    });

    test('an empty file is an ArgumentError, not a decode failure', () {
      expect(() => decodeOgg(Uint8List(0)), throwsArgumentError);
    });
  });
}
