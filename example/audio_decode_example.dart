// Decodes an audio file to PCM and writes it back out as a WAV.
//
// Usage:
//   dart run example/audio_decode_example.dart input.mp3 [output.wav]
//
// The input may be Ogg Vorbis or MP3; the format is detected from its bytes.
import 'dart:io';

import 'package:audio_decode/audio_decode.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run example/audio_decode_example.dart '
      'input.(ogg|mp3) [output.wav]',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final input = args[0];
  final bytes = File(input).readAsBytesSync();

  print('format: ${detectFormat(bytes).name}');

  final PcmAudio pcm;
  try {
    pcm = decodeAudio(bytes);
  } on AudioDecodeException catch (e) {
    stderr.writeln('could not decode $input: ${e.message}');
    exitCode = 65; // EX_DATAERR
    return;
  }

  print('sample rate: ${pcm.sampleRate} Hz');
  print('channels:    ${pcm.channels}');
  print('frames:      ${pcm.frameCount}');
  print('duration:    ${pcm.duration}');

  final output = args.length > 1 ? args[1] : '$input.wav';
  File(output).writeAsBytesSync(encodeWav(pcm));
  print('wrote $output (${pcm.samples.length * 2 + 44} bytes)');
}
