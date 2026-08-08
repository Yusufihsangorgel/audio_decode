// Decodes an audio file to PCM and writes it back out as a WAV.
//
// Usage:
//   dart run example/audio_decode_example.dart input.mp3 [output.wav]
//
// The input may be Ogg Vorbis, MP3 or WAV; the format is detected from its
// bytes, so the extension does not have to be right.
// With no argument it decodes a test tone that ships with the package, so the
// example runs before you have gone looking for an audio file.
//
// Given no output path, it writes into a fresh temp directory and prints where.
// Running an example should not leave a file in the directory you ran it from.
import 'dart:io';

import 'package:audio_decode/audio_decode.dart';

/// A one-second stereo Ogg Vorbis tone from the test fixtures.
const _sampleInput = 'test/fixtures/sine_44100_stereo_1s.ogg';

void main(List<String> args) {
  final input = args.isEmpty ? _sampleInput : args[0];
  if (args.isEmpty) {
    if (!File(input).existsSync()) {
      stderr.writeln(
        'usage: dart run example/audio_decode_example.dart '
        'input.(ogg|mp3|wav) [output.wav]\n'
        '($input is missing, so there is nothing to fall back to)',
      );
      exitCode = 64; // EX_USAGE
      return;
    }
    print('No input given, decoding $input.');
    print('It is a steady sine, so expect a flat waveform below.\n');
  }

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

  final wav = encodeWav(pcm);
  final output = File(args.length > 1 ? args[1] : _defaultOutputPath(input));
  output.writeAsBytesSync(wav);
  print('wrote ${output.path} (${wav.length} bytes)');
}

/// Where the WAV goes when the caller did not say.
///
/// A fresh temp directory, not the working directory: an example that drops a
/// file into whatever project you ran it from is a nuisance, and in a checkout
/// it shows up as a stray file in `git status`. `createTempSync` also means two
/// runs never collide, and never overwrite something already in the temp dir.
String _defaultOutputPath(String input) {
  final directory = Directory.systemTemp.createTempSync('audio_decode_example');
  // Both separators: a Windows caller passes `C:\music\clip.mp3`.
  final name = input.split(RegExp(r'[/\\]')).last;
  return '${directory.path}${Platform.pathSeparator}$name.wav';
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
