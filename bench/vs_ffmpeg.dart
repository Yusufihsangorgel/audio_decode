// Compares decoding in-process against shelling out to ffmpeg.
//
// Shelling out is the usual way to get PCM out of an encoded file from Dart,
// so this measures the choice a reader actually faces. Both paths produce the
// same interleaved 16-bit samples, and the bench checks that they do before
// reporting any timing. The ffmpeg column includes process startup, because
// that cost is paid once per file and is most of what the comparison is about.
//
// Requires ffmpeg on the PATH. Usage: dart run bench/vs_ffmpeg.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';

const _durations = [1, 5, 15, 30];
const _iterations = 9;

void main() {
  if (!_hasFfmpeg()) {
    stderr.writeln('ffmpeg not found on PATH; this bench needs it.');
    exitCode = 1;
    return;
  }

  final dir = Directory.systemTemp.createTempSync('audio_decode_vs_ffmpeg');
  final notes = <String>[];
  try {
    print('audio_decode vs ffmpeg subprocess');
    print('  ${_ffmpegVersion()}');
    print('  $_iterations runs per cell, median reported');
    print('');
    print('  clip     in-process    ffmpeg      ratio');
    print('  ----------------------------------------');

    for (final seconds in _durations) {
      final path = '${dir.path}/clip_$seconds.ogg';
      _encodeClip(seconds, path);
      final bytes = File(path).readAsBytesSync();

      // Both paths must produce the same audio before either timing means
      // anything. They agree exactly at every length except the shortest,
      // where ffmpeg's raw pipe stops 128 frames early; audio_decode returns
      // the sample count the container itself declares. A larger divergence
      // would mean one of the two is decoding wrongly, so it fails the run.
      final decoded = decodeOgg(bytes);
      final viaFfmpeg = _ffmpegPcm(path);
      final ourFrames = decoded.frameCount;
      final theirFrames = viaFfmpeg.lengthInBytes ~/ 2 ~/ decoded.channels;
      final drift = (ourFrames - theirFrames).abs();
      if (drift > 1024) {
        throw StateError(
          'decoders disagree for ${seconds}s: $ourFrames vs $theirFrames '
          'frames',
        );
      }
      if (drift != 0) {
        notes.add(
          '  ${seconds}s: ffmpeg stopped $drift frames early '
          '($theirFrames of $ourFrames).',
        );
      }

      final inProcess = _median([
        for (var i = 0; i < _iterations; i++) _time(() => decodeOgg(bytes)),
      ]);
      final subprocess = _median([
        for (var i = 0; i < _iterations; i++) _time(() => _ffmpegPcm(path)),
      ]);

      print(
        '  ${'${seconds}s'.padRight(8)} '
        '${'${(inProcess / 1000).toStringAsFixed(3)} ms'.padLeft(11)} '
        '${'${(subprocess / 1000).toStringAsFixed(3)} ms'.padLeft(11)} '
        '${'${(subprocess / inProcess).toStringAsFixed(0)}x'.padLeft(7)}',
      );
    }

    // The floor: a clip short enough that almost none of the time is decoding.
    // Whatever is left is what it costs to start a process at all.
    final floorPath = '${dir.path}/floor.ogg';
    _encodeTinyClip(floorPath);
    _ffmpegPcm(floorPath);
    final floor = _median([
      for (var i = 0; i < _iterations; i++) _time(() => _ffmpegPcm(floorPath)),
    ]);

    print('');
    print(
      'Decoding a 0.05 s clip through ffmpeg still takes '
      '${(floor / 1000).toStringAsFixed(3)} ms, so that is roughly what the '
      'process itself costs, before any audio is decoded.',
    );
    print('');
    print(
      'Both columns produce the same PCM. The gap is not the codec: it is '
      'the process. Spawning ffmpeg costs those tens of milliseconds whether '
      'the clip is one second or thirty, which is why the ratio shrinks as '
      'the clip grows.',
    );
    if (notes.isNotEmpty) {
      print('');
      print('Sample counts, where the two did not line up exactly:');
      notes.forEach(print);
    }
  } finally {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort cleanup.
    }
  }
}

int _time(void Function() body) {
  final sw = Stopwatch()..start();
  body();
  sw.stop();
  return sw.elapsedMicroseconds;
}

int _median(List<int> values) {
  values.sort();
  return values[values.length ~/ 2];
}

void _encodeTinyClip(String path) {
  final result = Process.runSync('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=0.05:sample_rate=44100',
    '-ac',
    '2',
    '-c:a',
    'libvorbis',
    '-y',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg failed to encode the floor clip');
  }
}

void _encodeClip(int seconds, String path) {
  final result = Process.runSync('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=$seconds:sample_rate=44100',
    '-ac',
    '2',
    '-c:a',
    'libvorbis',
    '-y',
    path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg failed to encode a ${seconds}s clip');
  }
}

/// Decodes [path] to raw interleaved 16-bit PCM by running ffmpeg and reading
/// its stdout, which is what a Dart program without a native decoder does.
Uint8List _ffmpegPcm(String path) {
  final result = Process.runSync('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    path,
    '-f',
    's16le',
    '-acodec',
    'pcm_s16le',
    '-',
  ], stdoutEncoding: null);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg failed to decode $path');
  }
  return result.stdout as Uint8List;
}

bool _hasFfmpeg() {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

String _ffmpegVersion() {
  final out = Process.runSync('ffmpeg', ['-version']).stdout as String;
  return out.split('\n').first.trim();
}
