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

  // What you actually do with the samples: reduce them to a waveform. Bucket the
  // frames into columns and take the peak amplitude in each, the same primitive
  // a waveform view or a silence detector is built on.
  print('waveform:    ${asciiWaveform(pcm)}');

  final output = args.length > 1 ? args[1] : '$input.wav';
  File(output).writeAsBytesSync(encodeWav(pcm));
  print('wrote $output (${pcm.samples.length * 2 + 44} bytes)');
}

/// Renders [pcm] as a one-line waveform of [width] columns. Each column is the
/// peak amplitude of its slice of frames, scaled to the loudest column so the
/// shape shows regardless of the recording's overall level.
String asciiWaveform(PcmAudio pcm, {int width = 64}) {
  const blocks = ' ▁▂▃▄▅▆▇█';
  final frames = pcm.frameCount;
  if (frames == 0) return '';
  final peaks = List<int>.filled(width, 0);
  var loudest = 1;
  for (var col = 0; col < width; col++) {
    final start = col * frames ~/ width;
    final end = (col + 1) * frames ~/ width;
    var peak = 0;
    for (var frame = start; frame < end; frame++) {
      for (var channel = 0; channel < pcm.channels; channel++) {
        final amplitude = pcm.samples[frame * pcm.channels + channel].abs();
        if (amplitude > peak) peak = amplitude;
      }
    }
    peaks[col] = peak;
    if (peak > loudest) loudest = peak;
  }
  final buffer = StringBuffer();
  for (final peak in peaks) {
    buffer.write(blocks[(peak * 8 ~/ loudest).clamp(0, 8)]);
  }
  return buffer.toString();
}
