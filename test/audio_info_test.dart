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

  test(
    'a per-channel sample count beyond int32 range is rejected, not wrapped',
    () {
      final unit = fixture('sine_44100_mono_1s.mp3');
      // Concatenating the one-second clip enough times pushes the total
      // per-channel sample count past 2,147,483,647 (2^31 - 1), the point
      // where the native int32 out-parameter would otherwise wrap to a
      // negative value instead of holding the true count.
      const repeats = 48000;
      final huge = Uint8List(unit.length * repeats);
      for (var i = 0; i < repeats; i++) {
        huge.setRange(i * unit.length, (i + 1) * unit.length, unit);
      }
      expect(() => mp3Info(huge), throwsA(isA<AudioDecodeException>()));
    },
  );

  test('a Vorbis granule beyond int32 range is rejected, not wrapped', () {
    final ogg = fixture('sine_44100_mono_1s.ogg');

    // Control: rewriting the final page's granule to a value that fits in
    // int32 and repairing the page checksum reads back as exactly that value.
    // This proves the crafting below is faithful, so the rejection is the
    // overflow guard firing rather than a corrupt page the decoder refused.
    expect(oggInfo(_withEosGranule(ogg, 1000)).frameCount, 1000);

    // Vorbis carries the stream length in the final page's granule position.
    // A granule of 2^31 is one past the int32 range (2,147,483,647), so
    // narrowing it into the native int out-parameter would wrap to a negative
    // frame count instead of holding the true length.
    expect(
      () => oggInfo(_withEosGranule(ogg, 1 << 31)),
      throwsA(isA<AudioDecodeException>()),
    );
  });

  group('AudioInfo value equality', () {
    // Built with runtime (non-const) constructors so the instances are
    // distinct objects; this exercises operator == rather than the compiler's
    // canonicalization of const instances.
    test('instances with equal fields are equal and share a hashCode', () {
      final a = AudioInfo(sampleRate: 44100, channels: 2, frameCount: 88200);
      final b = AudioInfo(sampleRate: 44100, channels: 2, frameCount: 88200);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equal instances collapse to one entry in a Set', () {
      final a = AudioInfo(sampleRate: 48000, channels: 1, frameCount: 24000);
      final b = AudioInfo(sampleRate: 48000, channels: 1, frameCount: 24000);
      expect({a, b}, hasLength(1));
    });

    test('a difference in any single field breaks equality', () {
      final base = AudioInfo(sampleRate: 44100, channels: 2, frameCount: 88200);
      expect(
        base,
        isNot(AudioInfo(sampleRate: 48000, channels: 2, frameCount: 88200)),
      );
      expect(
        base,
        isNot(AudioInfo(sampleRate: 44100, channels: 1, frameCount: 88200)),
      );
      expect(
        base,
        isNot(AudioInfo(sampleRate: 44100, channels: 2, frameCount: 44100)),
      );
    });
  });
}

/// The lookup table for the Ogg page checksum: a non-reflected CRC-32,
/// polynomial 0x04c11db7 with a zero initial value. This mirrors crc32_init in
/// the vendored stb_vorbis, whose `vorbis_find_page` rejects any page whose
/// stored checksum does not match, so a page whose granule has been rewritten
/// has to carry a recomputed one.
final Uint32List _oggCrcTable = () {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var crc = (i << 24) & 0xFFFFFFFF;
    for (var bit = 0; bit < 8; bit++) {
      final topSet = crc & 0x80000000 != 0;
      crc = ((crc << 1) & 0xFFFFFFFF) ^ (topSet ? 0x04c11db7 : 0);
    }
    table[i] = crc;
  }
  return table;
}();

/// The Ogg page checksum over [page], computed with its checksum field held at
/// zero, matching stb_vorbis's `crc32_update`.
int _oggPageCrc(Uint8List page) {
  var crc = 0;
  for (final byte in page) {
    crc =
        ((crc << 8) & 0xFFFFFFFF) ^ _oggCrcTable[(byte ^ (crc >>> 24)) & 0xFF];
  }
  return crc;
}

/// The byte range `[start, end)` of the stream's end-of-stream page, the last
/// page, identified by the 0x04 bit in its header type. Ogg pages are
/// self-describing: a 27-byte header, then one length byte per segment, then
/// the segment bodies.
(int, int) _eosPageRange(Uint8List bytes) {
  var offset = 0;
  while (offset + 27 <= bytes.length) {
    final headerType = bytes[offset + 5];
    final segmentCount = bytes[offset + 26];
    var bodySize = 0;
    for (var i = 0; i < segmentCount; i++) {
      bodySize += bytes[offset + 27 + i];
    }
    final pageSize = 27 + segmentCount + bodySize;
    if (headerType & 0x04 != 0) return (offset, offset + pageSize);
    offset += pageSize;
  }
  throw StateError('no end-of-stream page');
}

/// A copy of [bytes] whose end-of-stream page carries [granule] as its absolute
/// granule position, eight little-endian bytes at page offset 6, with the page
/// checksum recomputed so the decoder accepts it. stb_vorbis reads this granule
/// as the stream length.
Uint8List _withEosGranule(Uint8List bytes, int granule) {
  final crafted = Uint8List.fromList(bytes);
  final (start, end) = _eosPageRange(crafted);
  for (var i = 0; i < 8; i++) {
    crafted[start + 6 + i] = (granule >>> (8 * i)) & 0xFF;
  }
  // Zero the four-byte checksum field at page offset 22, then fill it with the
  // checksum of the whole page.
  for (var i = 0; i < 4; i++) {
    crafted[start + 22 + i] = 0;
  }
  final crc = _oggPageCrc(Uint8List.sublistView(crafted, start, end));
  for (var i = 0; i < 4; i++) {
    crafted[start + 22 + i] = (crc >>> (8 * i)) & 0xFF;
  }
  return crafted;
}
