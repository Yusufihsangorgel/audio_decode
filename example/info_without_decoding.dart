// The shape of a file, without paying for its samples.
//
//   dart run example/info_without_decoding.dart
//
// `audioInfo` reads the headers and stops. `decodeAudio` reads the headers and
// then decodes every sample into memory. If all you need is a duration, a
// sample rate or a channel count — a playlist showing track lengths, an upload
// whose length has to be checked before it is accepted, a batch job picking
// which files to process — the second one buys nothing and costs everything.
//
// Nothing in this directory used `audioInfo`, so the difference had never been
// put in front of a reader. It is worth a number.
import 'dart:io';

import 'package:audio_decode/audio_decode.dart';

/// The test fixtures, which are the only audio this repository ships.
const _fixtures = [
  'test/fixtures/sine_44100_stereo_1s.ogg',
  'test/fixtures/sine_44100_stereo_1s.mp3',
  'test/fixtures/sine_48000_mono_halfsec.mp3',
];

String kb(int bytes) => '${(bytes / 1024).round()} KB';

void main() {
  final present = _fixtures.where((p) => File(p).existsSync()).toList();
  if (present.isEmpty) {
    stderr.writeln(
      'Run this from the package root; it reads the test fixtures.\n'
      '  cd audio_decode && dart run example/info_without_decoding.dart',
    );
    exit(69); // EX_UNAVAILABLE
  }

  print('');
  print(
    '${'file'.padRight(34)}${'on disk'.padLeft(9)}'
    '${'decoded'.padLeft(10)}${'ratio'.padLeft(8)}',
  );
  print('  ${'-' * 59}');

  var totalCompressed = 0;
  var totalPcm = 0;

  for (final path in present) {
    final bytes = File(path).readAsBytesSync();

    // Headers only. No sample is touched.
    final info = audioInfo(bytes);

    // Every sample, in memory, as 32-bit floats.
    final pcm = decodeAudio(bytes);
    final pcmBytes = pcm.samples.length * 4;

    totalCompressed += bytes.length;
    totalPcm += pcmBytes;

    print(
      '${path.split('/').last.padRight(34)}'
      '${kb(bytes.length).padLeft(9)}${kb(pcmBytes).padLeft(10)}'
      '${'${(pcmBytes / bytes.length).round()}x'.padLeft(8)}',
    );
    print(
      '  ${info.sampleRate} Hz, ${info.channels} channel'
      '${info.channels == 1 ? '' : 's'}, '
      '${info.duration.inMilliseconds} ms — all of that from the headers',
    );
  }

  print('');
  print(
    '${present.length} files: ${kb(totalCompressed)} on disk, '
    '${kb(totalPcm)} decoded.',
  );
  print('');
  print('Those are one-second tones. A three-minute track at 44.1 kHz stereo');
  print(
    'is about 30 MB of float samples, and an album is most of a gigabyte —',
  );
  print('to print a running time you already have in the header.');
  print('');
  print('`audioInfo` picks the right reader from the bytes. `oggInfo` and');
  print('`mp3Info` are there when you already know the format and would');
  print('rather not have it guessed.');
}
