import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

/// Builds a WAV file around [payload] with a hand-written header, so a test
/// can produce bit depths and codecs [encodeWav] never writes.
Uint8List wavFile({
  required int formatTag,
  required int channels,
  required int sampleRate,
  required int bitsPerSample,
  required List<int> payload,
}) {
  final bytes = BytesBuilder();
  final header = ByteData(36);
  final blockAlign = (bitsPerSample ~/ 8) * channels;
  header.setUint32(0, 0x46464952, Endian.little); // 'RIFF'
  header.setUint32(4, 36 + payload.length, Endian.little);
  header.setUint32(8, 0x45564157, Endian.little); // 'WAVE'
  header.setUint32(12, 0x20746d66, Endian.little); // 'fmt '
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, formatTag, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * blockAlign, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  bytes.add(header.buffer.asUint8List());
  final data = ByteData(8)
    ..setUint32(0, 0x61746164, Endian.little) // 'data'
    ..setUint32(4, payload.length, Endian.little);
  bytes.add(data.buffer.asUint8List());
  bytes.add(payload);
  return bytes.toBytes();
}

void main() {
  group('decodeWav', () {
    test('reads back exactly what encodeWav wrote', () {
      // The package could write a WAV and then refuse to read it: encodeWav
      // existed while detectFormat did not know the RIFF signature, so its own
      // output came back as "unrecognized audio format".
      final original = PcmAudio(
        samples: Int16List.fromList(
          List.generate(2000, (i) => (i * 37) % 20000 - 10000),
        ),
        sampleRate: 44100,
        channels: 2,
      );
      final encoded = encodeWav(original);

      expect(detectFormat(encoded), AudioFormat.wav);
      final decoded = decodeAudio(encoded);
      expect(decoded.sampleRate, 44100);
      expect(decoded.channels, 2);
      expect(decoded.samples, original.samples);
    });

    test('reads 8-bit, which is unsigned unlike every other width', () {
      // 0 and 255 are the extremes and 128 is silence, so a decoder that
      // treated them as signed would read silence as a loud offset.
      final file = wavFile(
        formatTag: 1,
        channels: 1,
        sampleRate: 8000,
        bitsPerSample: 8,
        payload: [128, 255, 0, 128],
      );
      final pcm = decodeWav(file);
      expect(pcm.samples, [0, 32512, -32768, 0]);
    });

    test('reads 24-bit and 32-bit integer PCM', () {
      final wav24 = wavFile(
        formatTag: 1,
        channels: 1,
        sampleRate: 48000,
        bitsPerSample: 24,
        // Little-endian 24-bit: 0x000000 then 0x7FFF00 (near full scale).
        payload: [0x00, 0x00, 0x00, 0x00, 0xFF, 0x7F],
      );
      expect(decodeWav(wav24).samples, [0, 32767]);

      final wav32 = ByteData(8)
        ..setInt32(0, 0, Endian.little)
        ..setInt32(4, 0x7FFF0000, Endian.little);
      final file32 = wavFile(
        formatTag: 1,
        channels: 1,
        sampleRate: 48000,
        bitsPerSample: 32,
        payload: wav32.buffer.asUint8List(),
      );
      expect(decodeWav(file32).samples, [0, 32767]);
    });

    test('reads IEEE float and clamps values outside -1..1', () {
      // Recordings overshoot and broken encoders emit NaN; both would wrap to
      // a loud opposite-sign sample if they were scaled without a clamp.
      final payload = ByteData(20)
        ..setFloat32(0, 0, Endian.little)
        ..setFloat32(4, 1, Endian.little)
        ..setFloat32(8, -1, Endian.little)
        ..setFloat32(12, 1.8, Endian.little)
        ..setFloat32(16, double.nan, Endian.little);
      final file = wavFile(
        formatTag: 3,
        channels: 1,
        sampleRate: 44100,
        bitsPerSample: 32,
        payload: payload.buffer.asUint8List(),
      );
      expect(decodeWav(file).samples, [0, 32767, -32767, 32767, 0]);
    });

    test('names a compressed payload instead of decoding it as noise', () {
      final file = wavFile(
        formatTag: 0x0011, // IMA ADPCM
        channels: 1,
        sampleRate: 44100,
        bitsPerSample: 4,
        payload: List.filled(64, 0x40),
      );
      expect(
        () => decodeWav(file),
        throwsA(
          isA<AudioDecodeException>().having(
            (e) => e.toString(),
            'message',
            contains('IMA ADPCM'),
          ),
        ),
      );
    });

    test('rejects a file with no data chunk', () {
      final header = wavFile(
        formatTag: 1,
        channels: 1,
        sampleRate: 44100,
        bitsPerSample: 16,
        payload: const [],
      );
      // Cut the file off right after the fmt chunk.
      expect(
        () => decodeWav(Uint8List.sublistView(header, 0, 36)),
        throwsA(isA<AudioDecodeException>()),
      );
    });

    test('drops a partial frame rather than shifting the channels', () {
      // An odd number of samples in a stereo file cannot be a whole frame;
      // keeping it would put every later sample in the wrong channel.
      final file = wavFile(
        formatTag: 1,
        channels: 2,
        sampleRate: 44100,
        bitsPerSample: 16,
        payload: [1, 0, 2, 0, 3, 0],
      );
      expect(decodeWav(file).samples, hasLength(2));
    });
  });

  group('wavInfo', () {
    test('reports geometry from the header without decoding', () {
      final original = PcmAudio(
        samples: Int16List.fromList(List.filled(4410 * 2, 0)),
        sampleRate: 44100,
        channels: 2,
      );
      final info = audioInfo(encodeWav(original));
      expect(info.sampleRate, 44100);
      expect(info.channels, 2);
      expect(info.frameCount, 4410);
      expect(info.duration, const Duration(milliseconds: 100));
    });
  });
}
