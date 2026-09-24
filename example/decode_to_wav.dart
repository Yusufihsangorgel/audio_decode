// Decode one audio file and write the interleaved PCM as a WAV file.
//
// Usage:
//   dart run example/decode_to_wav.dart INPUT OUTPUT.wav
//
// Exit codes: 64 usage, 65 invalid audio, 66 input read failure,
// 74 output write failure.
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run example/decode_to_wav.dart INPUT OUTPUT.wav',
    );
    stderr.writeln(
      'exit codes: 64 usage, 65 invalid audio, 66 input read, 74 output write',
    );
    exitCode = 64;
    return;
  }

  final Uint8List bytes;
  try {
    bytes = File(args[0]).readAsBytesSync();
  } on FileSystemException catch (error) {
    stderr.writeln('error 66 (input read): ${args[0]}: $error');
    exitCode = 66;
    return;
  }

  final PcmAudio pcm;
  try {
    pcm = decodeAudio(bytes);
  } on AudioDecodeException catch (error) {
    stderr.writeln('error 65 (invalid audio): ${args[0]}: ${error.message}');
    exitCode = 65;
    return;
  } on ArgumentError catch (error) {
    stderr.writeln('error 65 (invalid audio): ${args[0]}: $error');
    exitCode = 65;
    return;
  }

  final wav = encodeWav(pcm);
  try {
    File(args[1]).writeAsBytesSync(wav);
  } on FileSystemException catch (error) {
    stderr.writeln('error 74 (output write): ${args[1]}: $error');
    exitCode = 74;
    return;
  }

  stdout.writeln(
    'wrote ${args[1]} (${pcm.sampleRate} Hz, ${pcm.channels} channels, '
    '${wav.length} bytes)',
  );
}
