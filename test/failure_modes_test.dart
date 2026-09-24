import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

void main() {
  group('inputs the decoders reject', () {
    test('a truncated WAV fmt chunk throws AudioDecodeException', () {
      final bytes = Uint8List(28);
      final data = ByteData.sublistView(bytes);
      data.setUint32(4, 20, Endian.little);
      data.setUint32(16, 16, Endian.little);
      bytes.setRange(0, 4, 'RIFF'.codeUnits);
      bytes.setRange(8, 12, 'WAVE'.codeUnits);
      bytes.setRange(12, 16, 'fmt '.codeUnits);

      expect(
        () => decodeAudio(bytes),
        throwsA(
          isA<AudioDecodeException>().having(
            (error) => error.message,
            'message',
            'WAV fmt chunk is truncated',
          ),
        ),
      );
    });

    test('a recognized WAV file without a fmt chunk is corrupt input', () {
      final bytes = Uint8List(12);
      ByteData.sublistView(bytes).setUint32(4, 4, Endian.little);
      bytes.setRange(0, 4, 'RIFF'.codeUnits);
      bytes.setRange(8, 12, 'WAVE'.codeUnits);

      expect(detectFormat(bytes), AudioFormat.wav);
      expect(
        () => decodeAudio(bytes),
        throwsA(
          isA<AudioDecodeException>().having(
            (error) => error.message,
            'message',
            'WAV file has no fmt chunk',
          ),
        ),
      );
    });

    test('an unsupported FLAC signature is reported as unrecognized', () {
      final bytes = Uint8List.fromList('fLaC'.codeUnits);

      expect(detectFormat(bytes), AudioFormat.unknown);
      expect(
        () => decodeAudio(bytes),
        throwsA(
          isA<AudioDecodeException>().having(
            (error) => error.message,
            'message',
            'unrecognized audio format',
          ),
        ),
      );
    });
  });
}
