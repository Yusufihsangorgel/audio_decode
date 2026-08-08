import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

/// A sine at [hz], [seconds] long, at [rate].
PcmAudio tone(
  double hz, {
  int rate = 44100,
  double seconds = 0.25,
  int channels = 1,
}) {
  final frames = (rate * seconds).round();
  final samples = Int16List(frames * channels);
  for (var frame = 0; frame < frames; frame++) {
    final value = (math.sin(2 * math.pi * hz * frame / rate) * 20000).round();
    for (var channel = 0; channel < channels; channel++) {
      samples[frame * channels + channel] = value;
    }
  }
  return PcmAudio(sampleRate: rate, channels: channels, samples: samples);
}

/// Energy at [hz] in [audio], by correlating against that frequency.
///
/// A full DFT would say the same thing about one bin; this is the one bin the
/// tests ask about.
double energyAt(PcmAudio audio, double hz) {
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

void main() {
  group('toMono', () {
    test('averages the channels rather than dropping one', () {
      final stereo = PcmAudio(
        sampleRate: 8000,
        channels: 2,
        samples: Int16List.fromList([1000, 2000, -300, -100, 5, 6]),
      );
      expect(toMono(stereo).samples, equals([1500, -200, 6]));
      expect(toMono(stereo).channels, equals(1));
      expect(toMono(stereo).sampleRate, equals(8000));
    });

    test('is a no-op on mono', () {
      final mono = tone(440);
      expect(identical(toMono(mono), mono), isTrue);
    });

    test('does not clip when both channels are at full scale', () {
      final loud = PcmAudio(
        sampleRate: 8000,
        channels: 2,
        samples: Int16List.fromList([32767, 32767, -32768, -32768]),
      );
      expect(toMono(loud).samples, equals([32767, -32768]));
    });
  });

  group('resample', () {
    test('keeps a tone that fits in the target band', () {
      final source = tone(1000);
      final out = resample(source, 16000);

      expect(out.sampleRate, equals(16000));
      expect(out.frameCount, closeTo(source.frameCount * 16000 / 44100, 2));
      // The tone survives: still the dominant energy at 1 kHz.
      expect(energyAt(out, 1000), greaterThan(0.3 * energyAt(source, 1000)));
    });

    test('suppresses a tone above the target Nyquist instead of folding it', () {
      // 12 kHz at 44.1 kHz cannot exist at 16 kHz: without a low-pass it comes
      // back as 16000 - 12000 = 4000 Hz, a tone that was never recorded. This
      // is the assertion the whole filter exists for.
      final source = tone(12000);
      final out = resample(source, 16000);

      final aliasEnergy = energyAt(out, 4000);
      final originalEnergy = energyAt(source, 12000);
      expect(
        aliasEnergy,
        lessThan(0.05 * originalEnergy),
        reason: 'a 12 kHz tone folded back to 4 kHz; the low-pass did not run',
      );
    });

    test('upsampling does not need the filter and keeps the tone', () {
      final source = tone(1000, rate: 8000);
      final out = resample(source, 16000);

      expect(out.sampleRate, equals(16000));
      expect(out.frameCount, closeTo(source.frameCount * 2, 2));
      expect(energyAt(out, 1000), greaterThan(0.3 * energyAt(source, 1000)));
    });

    test('preserves the channel count', () {
      final stereo = tone(1000, channels: 2);
      final out = resample(stereo, 22050);
      expect(out.channels, equals(2));
      expect(out.samples.length, equals(out.frameCount * 2));
    });

    test('is a no-op at the same rate', () {
      final source = tone(1000);
      expect(identical(resample(source, 44100), source), isTrue);
    });

    test('empty audio resamples to empty at the new rate', () {
      final empty = PcmAudio(
        sampleRate: 44100,
        channels: 2,
        samples: Int16List(0),
      );
      final out = resample(empty, 16000);
      expect(out.samples, isEmpty);
      expect(out.sampleRate, equals(16000));
      expect(out.channels, equals(2));
    });

    test('rejects a non-positive target rate', () {
      expect(() => resample(tone(440), 0), throwsArgumentError);
      expect(() => resample(tone(440), -16000), throwsArgumentError);
    });
  });

  group('toSpeechPcm', () {
    test('gives 16 kHz mono from 44.1 kHz stereo', () {
      final source = tone(440, channels: 2);
      final out = toSpeechPcm(source);

      expect(out.sampleRate, equals(16000));
      expect(out.channels, equals(1));
      expect(out.frameCount, closeTo(source.frameCount * 16000 / 44100, 2));
      expect(energyAt(out, 440), greaterThan(0.3 * energyAt(source, 440)));
    });

    test('honours a different model rate', () {
      expect(toSpeechPcm(tone(440), sampleRate: 8000).sampleRate, equals(8000));
    });
  });
}
