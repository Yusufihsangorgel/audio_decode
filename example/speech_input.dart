// Turns a decoded audio file into the input an on-device speech model asks
// for: 16 kHz, mono, 16-bit PCM.
//
// Usage:
//   dart run example/speech_input.dart [input.(ogg|mp3|wav)] [output.wav]
//
// With no argument it uses a one-second stereo fixture that ships with the
// package, so the example runs before you have gone looking for an audio file.
// Given no output path, it writes into a fresh temp directory and prints where,
// rather than leaving a WAV in the directory you ran it from.
//
// Why this step exists at all: Whisper, wav2vec 2.0 and the Vosk family all
// want the same shape, and a decoded file is almost never in it — 44.1 kHz
// stereo is the normal case. Some wrappers convert for you by bundling ffmpeg;
// on the platforms where they do not, and for the ones that never convert, the
// conversion is the caller's job. The README's "Feeding a speech model"
// section says which wrapper does what.
//
// The second half of the output is the part worth reading twice: it measures
// what skipping the low-pass filter would cost, on your machine, in your build.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';

/// A one-second stereo Ogg Vorbis tone from the test fixtures.
const _sampleInput = 'test/fixtures/sine_44100_stereo_1s.ogg';

/// What the speech models in the README ask for.
const _modelRate = 16000;

void main(List<String> args) {
  final input = args.isEmpty ? _sampleInput : args[0];
  if (args.isEmpty && !File(input).existsSync()) {
    stderr.writeln(
      'usage: dart run example/speech_input.dart '
      'input.(ogg|mp3|wav) [output.wav]\n'
      '($input is missing, so there is nothing to fall back to)',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final PcmAudio source;
  try {
    source = decodeAudio(File(input).readAsBytesSync());
  } on AudioDecodeException catch (e) {
    stderr.writeln('could not decode $input: ${e.message}');
    exitCode = 65; // EX_DATAERR
    return;
  }

  // The whole conversion. `toSpeechPcm` is `resample(toMono(audio), 16000)`;
  // both halves are public if you want one without the other, and the rate is
  // a parameter for a model that wants 8 kHz.
  final speech = toSpeechPcm(source, sampleRate: _modelRate);

  print('decoded $input');
  print('  before  ${_shape(source)}');
  print('  after   ${_shape(speech)}');
  print(
    '  ${(source.samples.length / speech.samples.length).toStringAsFixed(1)}x '
    'fewer samples to push through the model',
  );

  // Write it as a WAV rather than a bare buffer: that is the form the wrappers
  // above accept from disk, so this file can go straight to one of them.
  final output = File(args.length > 1 ? args[1] : _defaultOutputPath());
  final wav = encodeWav(speech);
  output.writeAsBytesSync(wav);
  print(
    '  wrote ${output.path} (${wav.length} bytes) — 16 kHz mono, feed this in',
  );

  _showWhatTheFilterBuys();
}

/// Where the WAV goes when the caller did not say.
///
/// A fresh temp directory, not the working directory: an example that drops a
/// file into whatever project you ran it from is a nuisance, and in a checkout
/// it shows up as a stray file in `git status`. `createTempSync` also means two
/// runs never collide, and never overwrite something already in the temp dir.
String _defaultOutputPath() {
  final directory = Directory.systemTemp.createTempSync('audio_decode_speech');
  return '${directory.path}${Platform.pathSeparator}speech_input_16k_mono.wav';
}

String _shape(PcmAudio pcm) =>
    '${pcm.sampleRate.toString().padLeft(5)} Hz  '
    '${pcm.channels} ch  '
    '${pcm.frameCount.toString().padLeft(6)} frames  '
    '${pcm.samples.length.toString().padLeft(6)} samples  '
    '${pcm.duration}';

/// Measures the one thing about downsampling that is easy to get wrong.
///
/// Dropping 44.1 kHz to 16 kHz throws away every frequency above 8 kHz — but
/// only if you remove it first. Decimating without a filter does not delete
/// those frequencies, it *moves* them: a 12 kHz tone reappears at
/// 16000 - 12000 = 4000 Hz, indistinguishable from a tone that was really
/// recorded there, and no later processing can separate the two.
///
/// The package's `resample` low-passes before it decimates, and the test suite
/// pins the result at under 5% of the source tone's energy. This recomputes
/// that number next to the unfiltered version so the difference is a figure
/// rather than a claim.
void _showWhatTheFilterBuys() {
  const toneHz = 12000.0;
  // Where the tone lands once it is decimated: reflected about the new
  // Nyquist, so 16000 - 12000 = 4000 Hz.
  const aliasHz = _modelRate - toneHz;
  final source = _tone(toneHz, rate: 44100);
  final reference = _energyAt(source, toneHz);

  final filtered = resample(source, _modelRate);
  final unfiltered = _decimateWithoutFiltering(source, _modelRate);

  print('');
  print('what the low-pass buys, measured on a ${toneHz ~/ 1000} kHz tone');
  print(
    '  at $_modelRate Hz that tone cannot exist, so it folds back to '
    '${aliasHz.toInt()} Hz',
  );
  print('  resample()             ${_percentOf(filtered, aliasHz, reference)}');
  print(
    '  decimation, no filter  ${_percentOf(unfiltered, aliasHz, reference)}',
  );
  print('  the unfiltered run is the tone, intact, at a frequency nobody');
  print('  recorded — which is why resample() filters before it decimates.');
}

String _percentOf(PcmAudio audio, double hz, double reference) {
  final ratio = _energyAt(audio, hz) / reference;
  return '${(ratio * 100).toStringAsFixed(1).padLeft(5)}% '
      'of the source tone survives at ${hz.toInt()} Hz';
}

/// A sine at [hz], one quarter second long. Matches the test suite's helper so
/// the number printed above is the number the tests assert on.
PcmAudio _tone(double hz, {required int rate}) {
  final frames = rate ~/ 4;
  final samples = Int16List(frames);
  for (var frame = 0; frame < frames; frame++) {
    samples[frame] = (math.sin(2 * math.pi * hz * frame / rate) * 20000)
        .round();
  }
  return PcmAudio(sampleRate: rate, channels: 1, samples: samples);
}

/// Mono decimation with no filter: the loop you write when you need 16 kHz and
/// reach for the obvious thing. It is here to be measured, not to be copied.
PcmAudio _decimateWithoutFiltering(PcmAudio audio, int targetRate) {
  final step = audio.sampleRate / targetRate;
  final frames = (audio.frameCount / step).floor();
  final out = Int16List(frames);
  for (var frame = 0; frame < frames; frame++) {
    final index = (frame * step).round().clamp(0, audio.frameCount - 1);
    out[frame] = audio.samples[index];
  }
  return PcmAudio(sampleRate: targetRate, channels: 1, samples: out);
}

/// Energy at [hz], by correlating [audio] against that frequency.
///
/// A full DFT would say the same thing about one bin; this is the one bin the
/// question is about.
double _energyAt(PcmAudio audio, double hz) {
  var real = 0.0;
  var imaginary = 0.0;
  final frames = audio.frameCount;
  for (var frame = 0; frame < frames; frame++) {
    final angle = 2 * math.pi * hz * frame / audio.sampleRate;
    final sample = audio.samples[frame * audio.channels].toDouble();
    real += sample * math.cos(angle);
    imaginary += sample * math.sin(angle);
  }
  return math.sqrt(real * real + imaginary * imaginary) / frames;
}
