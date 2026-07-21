import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_decode/audio_decode.dart';
import 'package:test/test.dart';

/// Reads a committed fixture from `test/fixtures/`.
Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

/// Root-mean-square amplitude of channel 0, a simple non-silence measure.
double rms(PcmAudio audio) {
  final channels = audio.channels;
  final frames = audio.frameCount;
  if (frames == 0) return 0;
  var sum = 0.0;
  for (var i = 0; i < frames; i++) {
    final v = audio.samples[i * channels].toDouble();
    sum += v * v;
  }
  return math.sqrt(sum / frames);
}

/// Magnitude of the [frequency] component in channel 0, computed by direct
/// correlation against a complex sinusoid (a single-bin DFT). Used to confirm
/// the decoded signal really is a tone at the expected pitch.
double energyAt(PcmAudio audio, double frequency) {
  final channels = audio.channels;
  final frames = audio.frameCount;
  final rate = audio.sampleRate;
  var re = 0.0;
  var im = 0.0;
  for (var i = 0; i < frames; i++) {
    final v = audio.samples[i * channels].toDouble();
    final t = i / rate;
    final phase = 2 * math.pi * frequency * t;
    re += v * math.cos(phase);
    im += v * math.sin(phase);
  }
  return math.sqrt(re * re + im * im);
}

void main() {
  group('detectFormat', () {
    test('recognises Ogg by its OggS capture pattern', () {
      expect(detectFormat(fixture('sine_44100_mono_1s.ogg')), AudioFormat.ogg);
    });

    test('recognises MP3 fixtures', () {
      expect(detectFormat(fixture('sine_44100_mono_1s.mp3')), AudioFormat.mp3);
    });

    test('recognises a raw MPEG frame sync (0xFF 0xFB)', () {
      final frame = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00]);
      expect(detectFormat(frame), AudioFormat.mp3);
    });

    test('recognises an ID3v2 tag header', () {
      final id3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x03, 0x00]);
      expect(detectFormat(id3), AudioFormat.mp3);
    });

    test('reports unknown for garbage', () {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(detectFormat(garbage), AudioFormat.unknown);
    });

    test('reports unknown for empty and too-short input', () {
      expect(detectFormat(Uint8List(0)), AudioFormat.unknown);
      expect(detectFormat(Uint8List.fromList([0xFF])), AudioFormat.unknown);
    });
  });

  group('decodeOgg', () {
    test('mono 44100 Hz: geometry and length', () {
      final pcm = decodeOgg(fixture('sine_44100_mono_1s.ogg'));
      expect(pcm.sampleRate, 44100);
      expect(pcm.channels, 1);
      // Vorbis carries a little encoder delay/padding; the full decode is very
      // close to one second of samples.
      expect((pcm.frameCount - 44100).abs(), lessThan(2048));
      expect(pcm.samples.length, pcm.frameCount * pcm.channels);
    });

    test('stereo 44100 Hz: two channels', () {
      final pcm = decodeOgg(fixture('sine_44100_stereo_1s.ogg'));
      expect(pcm.channels, 2);
      expect(pcm.sampleRate, 44100);
      expect(pcm.samples.length, pcm.frameCount * 2);
    });

    test('mono 48000 Hz: sample rate honoured', () {
      final pcm = decodeOgg(fixture('sine_48000_mono_halfsec.ogg'));
      expect(pcm.sampleRate, 48000);
      expect(pcm.channels, 1);
      expect((pcm.frameCount - 24000).abs(), lessThan(2048));
    });

    test('decoded signal is a real 440 Hz tone', () {
      final pcm = decodeOgg(fixture('sine_44100_mono_1s.ogg'));
      expect(rms(pcm), greaterThan(500), reason: 'must not be silence');
      final at440 = energyAt(pcm, 440);
      final at1000 = energyAt(pcm, 1000);
      expect(
        at440,
        greaterThan(at1000 * 20),
        reason: '440 Hz should dominate 1000 Hz',
      );
    });

    test('duration is about one second', () {
      final pcm = decodeOgg(fixture('sine_44100_mono_1s.ogg'));
      expect(pcm.duration.inMilliseconds, closeTo(1000, 60));
    });
  });

  group('decodeMp3', () {
    test('mono 44100 Hz: geometry and plausible length', () {
      final pcm = decodeMp3(fixture('sine_44100_mono_1s.mp3'));
      expect(pcm.sampleRate, 44100);
      expect(pcm.channels, 1);
      // MP3 adds decoder delay, so the count runs a bit over one second; assert
      // it decoded a plausible number of frames rather than an exact count.
      expect(pcm.frameCount, greaterThan((0.8 * 44100).round()));
      expect(pcm.frameCount, lessThan(44100 + 4096));
      expect(pcm.samples.length, pcm.frameCount * pcm.channels);
    });

    test('stereo 44100 Hz: two channels', () {
      final pcm = decodeMp3(fixture('sine_44100_stereo_1s.mp3'));
      expect(pcm.channels, 2);
      expect(pcm.sampleRate, 44100);
      expect(pcm.frameCount, greaterThan((0.8 * 44100).round()));
    });

    test('mono 48000 Hz: sample rate honoured', () {
      final pcm = decodeMp3(fixture('sine_48000_mono_halfsec.mp3'));
      expect(pcm.sampleRate, 48000);
      expect(pcm.channels, 1);
      expect(pcm.frameCount, greaterThan((0.8 * 24000).round()));
    });

    test('decoded signal is a real 440 Hz tone', () {
      final pcm = decodeMp3(fixture('sine_44100_mono_1s.mp3'));
      expect(rms(pcm), greaterThan(500), reason: 'must not be silence');
      final at440 = energyAt(pcm, 440);
      final at1000 = energyAt(pcm, 1000);
      expect(
        at440,
        greaterThan(at1000 * 20),
        reason: '440 Hz should dominate 1000 Hz',
      );
    });
  });

  group('decodeAudio', () {
    test('auto-detects and decodes Ogg', () {
      final pcm = decodeAudio(fixture('sine_44100_stereo_1s.ogg'));
      expect(pcm.channels, 2);
      expect(pcm.sampleRate, 44100);
    });

    test('auto-detects and decodes MP3', () {
      final pcm = decodeAudio(fixture('sine_48000_mono_halfsec.mp3'));
      expect(pcm.channels, 1);
      expect(pcm.sampleRate, 48000);
    });
  });

  group('errors', () {
    test('empty bytes throw ArgumentError', () {
      expect(() => decodeOgg(Uint8List(0)), throwsArgumentError);
      expect(() => decodeMp3(Uint8List(0)), throwsArgumentError);
      expect(() => decodeAudio(Uint8List(0)), throwsArgumentError);
    });

    test('garbage throws AudioDecodeException', () {
      final garbage = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 37) & 0xFF),
      );
      expect(() => decodeOgg(garbage), throwsA(isA<AudioDecodeException>()));
      expect(() => decodeMp3(garbage), throwsA(isA<AudioDecodeException>()));
    });

    test('decodeAudio on unrecognised bytes throws with a clear message', () {
      final garbage = Uint8List.fromList([9, 9, 9, 9, 9, 9, 9, 9]);
      expect(
        () => decodeAudio(garbage),
        throwsA(
          isA<AudioDecodeException>().having(
            (e) => e.message,
            'message',
            contains('unrecognized'),
          ),
        ),
      );
    });

    test('decoding Ogg bytes with the MP3 decoder fails cleanly', () {
      expect(
        () => decodeMp3(fixture('sine_44100_mono_1s.ogg')),
        throwsA(isA<AudioDecodeException>()),
      );
    });
  });

  group('encodeWav', () {
    test('writes a canonical 16-bit PCM header for a known signal', () {
      final samples = Int16List.fromList([0, 1, -1, 2, -2, 3, -3, 4]);
      final audio = PcmAudio(sampleRate: 8000, channels: 2, samples: samples);
      final wav = encodeWav(audio);
      final view = ByteData.sublistView(wav);

      String ascii(int offset, int length) =>
          String.fromCharCodes(wav.sublist(offset, offset + length));

      expect(ascii(0, 4), 'RIFF');
      expect(ascii(8, 4), 'WAVE');
      expect(ascii(12, 4), 'fmt ');
      expect(ascii(36, 4), 'data');

      expect(view.getUint32(16, Endian.little), 16); // fmt chunk size
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 2); // channels
      expect(view.getUint32(24, Endian.little), 8000); // sample rate
      expect(view.getUint32(28, Endian.little), 8000 * 2 * 2); // byte rate
      expect(view.getUint16(32, Endian.little), 2 * 2); // block align
      expect(view.getUint16(34, Endian.little), 16); // bits per sample

      final dataLength = samples.length * 2;
      expect(view.getUint32(40, Endian.little), dataLength);
      expect(view.getUint32(4, Endian.little), 36 + dataLength); // RIFF size
      expect(wav.length, 44 + dataLength);

      // The PCM payload equals the input samples.
      for (var i = 0; i < samples.length; i++) {
        expect(view.getInt16(44 + i * 2, Endian.little), samples[i]);
      }
    });

    test('round-trips a decoded clip: header matches the source geometry', () {
      final pcm = decodeOgg(fixture('sine_44100_stereo_1s.ogg'));
      final wav = encodeWav(pcm);
      final view = ByteData.sublistView(wav);
      expect(view.getUint16(22, Endian.little), pcm.channels);
      expect(view.getUint32(24, Endian.little), pcm.sampleRate);
      expect(view.getUint16(34, Endian.little), 16);
      expect(view.getUint32(40, Endian.little), pcm.samples.length * 2);
      expect(wav.length, 44 + pcm.samples.length * 2);
    });
  });

  group('PcmAudio', () {
    test('frameCount and duration derive from geometry', () {
      final audio = PcmAudio(
        sampleRate: 16000,
        channels: 2,
        samples: Int16List(16000 * 2),
      );
      expect(audio.frameCount, 16000);
      expect(audio.duration, const Duration(seconds: 1));
    });

    test('toFloat32 normalizes each sample into [-1, 1]', () {
      final audio = PcmAudio(
        sampleRate: 8000,
        channels: 1,
        samples: Int16List.fromList([0, -32768, 16384, 32767]),
      );
      final f = audio.toFloat32();
      expect(f, isA<Float32List>());
      expect(f.length, 4);
      expect(f[0], 0.0);
      expect(f[1], -1.0); // full-scale negative maps exactly to -1.0
      expect(f[2], 0.5); // 16384 / 32768
      expect(f[3], closeTo(32767 / 32768, 1e-6));
    });

    test('channel deinterleaves and normalizes one channel', () {
      // Two frames of stereo: left = [-32768, 16384], right = [0, 32767].
      final audio = PcmAudio(
        sampleRate: 8000,
        channels: 2,
        samples: Int16List.fromList([-32768, 0, 16384, 32767]),
      );
      final left = audio.channel(0);
      final right = audio.channel(1);
      expect(left.length, 2);
      expect(right.length, 2);
      expect(left[0], -1.0);
      expect(left[1], 0.5);
      expect(right[0], 0.0);
      expect(right[1], closeTo(32767 / 32768, 1e-6));
    });

    test('channel rejects an out-of-range index', () {
      final audio = PcmAudio(
        sampleRate: 8000,
        channels: 2,
        samples: Int16List.fromList([1, 2, 3, 4]),
      );
      expect(() => audio.channel(-1), throwsRangeError);
      expect(() => audio.channel(2), throwsRangeError);
    });

    test('toMono averages the channels frame by frame', () {
      // Frame 0: (100 + 200) / 2 = 150. Frame 1: (-1000 + 2000) / 2 = 500.
      final audio = PcmAudio(
        sampleRate: 8000,
        channels: 2,
        samples: Int16List.fromList([100, 200, -1000, 2000]),
      );
      final mono = audio.toMono();
      expect(mono.channels, 1);
      expect(mono.sampleRate, 8000);
      expect(mono.frameCount, 2);
      expect(mono.samples, [150, 500]);
    });

    test('toMono returns already-mono audio unchanged', () {
      final audio = PcmAudio(
        sampleRate: 8000,
        channels: 1,
        samples: Int16List.fromList([1, 2, 3]),
      );
      expect(identical(audio.toMono(), audio), isTrue);
    });
  });
}
