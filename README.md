![audio_decode banner](https://raw.githubusercontent.com/Yusufihsangorgel/audio_decode/main/doc/banner.png)

# audio_decode

![Compressed bytes are decoded to PCM samples](https://raw.githubusercontent.com/Yusufihsangorgel/audio_decode/main/doc/architecture.png)

Native Ogg Vorbis and MP3 decoding to raw PCM for Dart, over FFI, plus WAV in pure Dart. The C
decoders are compiled from source by a Dart build hook, so the package is
self-contained: no platform plugins, no bundled binary, and no system library to
install beyond a C toolchain.

The same code path runs in pure Dart (command-line tools, servers, tests) and
in Flutter. That makes it a good fit for waveform rendering, audio analysis,
resampling, machine-learning preprocessing, servers and games.

Decoding is deterministic for a given build: the same bytes decode to the same
samples every time, and the geometry (channel count, sample rate, frame count)
is the same everywhere. Sample values are not bit-identical across CPU
architectures, though. Both decoders compute in floating point, and a compiler
is free to fuse a multiply and an add on arm64 where it does not on baseline
x86-64, so the last rounding can land differently. Measured across this
package's own fixtures, that is around 0.03% of samples differing by one
least-significant bit: inaudible, but enough that a checksum of decoded PCM
will not match across a mixed-architecture fleet.

It is built on two well-known public-domain single-file libraries:

- Ogg Vorbis: [stb_vorbis](https://github.com/nothings/stb) by Sean Barrett.
- MP3: [minimp3](https://github.com/lieff/minimp3) by lieff.

## What this is not

This is a decoder, not a player. It turns encoded bytes into PCM samples; it
does not open audio devices or handle playback, streaming or seeking. For
playback, use a player package such as
[just_audio](https://pub.dev/packages/just_audio) or
[flutter_sound](https://pub.dev/packages/flutter_sound).

Scope:

- Decodes Ogg Vorbis, MP3 and uncompressed WAV to interleaved signed 16-bit
  PCM. WAV needs no native code and covers 8/16/24/32-bit integer and IEEE
  float, so `encodeWav` output reads straight back.
- Encodes PCM back to a 16-bit WAV file (`encodeWav`), so decoded audio can be
  saved or handed to other tools.
- No encoding to Vorbis or MP3, and no other container or codec.

## Quick start

```dart
import 'dart:io';
import 'package:audio_decode/audio_decode.dart';

void main() {
  final bytes = File('clip.mp3').readAsBytesSync();

  // Auto-detects Ogg Vorbis, MP3 or WAV from the bytes.
  final pcm = decodeAudio(bytes);
  print('${pcm.sampleRate} Hz, ${pcm.channels} ch, ${pcm.duration}');
  print('${pcm.frameCount} frames, ${pcm.samples.length} interleaved samples');

  // Save the decoded audio as a WAV.
  File('clip.wav').writeAsBytesSync(encodeWav(pcm));
}
```

Decode a specific format directly when you already know it:

```dart
final ogg = decodeOgg(await File('clip.ogg').readAsBytes());
final mp3 = decodeMp3(await File('clip.mp3').readAsBytes());
```

## API

- `PcmAudio` holds the result: `sampleRate`, `channels`, and `samples` (an
  `Int16List` of samples interleaved by channel). It exposes `frameCount` and
  `duration`, plus `toFloat32()`, `channel(int)` and `toMono()` for the
  normalized and per-channel forms described below.
- `decodeAudio(Uint8List)` sniffs the format and dispatches.
- `decodeOgg(Uint8List)` and `decodeMp3(Uint8List)` decode a known format.
- `detectFormat(Uint8List)` returns `AudioFormat.ogg`, `AudioFormat.mp3` or
  `AudioFormat.unknown`.
- `encodeWav(PcmAudio)` returns a canonical 16-bit PCM WAV as `Uint8List`.
- `audioInfo(Uint8List)` returns an `AudioInfo` with `sampleRate`, `channels`,
  `frameCount` and `duration` without decoding to PCM; `oggInfo` and `mp3Info`
  do the same for a known format. See below.

Empty input throws `ArgumentError`. Bytes that are not decodable audio throw
`AudioDecodeException`.

A *truncated* file mostly does not throw, in either format, and an earlier
version of this section claimed otherwise. Measured across a sweep of
truncation points on a committed fixture:

- **Cut inside the header:** throws `AudioDecodeException`. Ogg gets this far
  because the header pages fail their checksum; there is nothing to decode.
- **Cut after the header:** decodes the audio that arrived and returns it, no
  exception. Ogg has per-page checksums, but the pages that did arrive are
  intact, so nothing is detectably wrong. Detecting the missing tail needs the
  end-of-stream page flag, which this package does not check yet.
- **Cut that yields no frames at all:** throws, since 1.0.1. This used to
  return success with `frameCount == 0`, which meant an upload check that only
  looked for an exception accepted a file containing no audio.

MP3 is worse by construction: a bare sequence of frames with no length anywhere
in it, so a cut-off file is indistinguishable from a shorter recording. A file
truncated to a third of its length decodes to roughly a third of the audio.

So if you are decoding something that may be incomplete, a partial download or
a stream you cut, compare the duration you expected against `PcmAudio.duration`.
Do not rely on an exception.

Samples are copied out of native memory before each call returns, so there is
no native buffer for the caller to manage.

## Normalized and per-channel samples

`samples` is raw interleaved `Int16List`, but FFT, machine-learning and
waveform code almost always wants floats in `[-1.0, 1.0]`, and often one
channel at a time. `PcmAudio` provides those directly so you do not hand-roll a
divide-by-32768 loop:

```dart
final pcm = decodeAudio(bytes);

// All channels, interleaved, normalized to [-1.0, 1.0].
final Float32List f = pcm.toFloat32();

// One channel, deinterleaved and normalized. 0 is left, 1 is right.
final Float32List left = pcm.channel(0);

// Average the channels down to a single mono PcmAudio.
final PcmAudio mono = pcm.toMono();
```

Each 16-bit sample is divided by 32768, so -32768 becomes -1.0 and 16384
becomes 0.5. `toMono()` returns the audio unchanged when it is already mono.

## Duration without decoding

Showing track lengths in a playlist, validating an upload, or picking which
files to process only needs a file's shape, not its samples. Decoding for that
is expensive: four minutes of 44.1 kHz stereo is 40 MB of PCM, and you throw
all of it away to read one number.

`audioInfo` answers from the stream itself and allocates no PCM at all:

```dart
final info = audioInfo(await File('track.mp3').readAsBytes());
print('${info.duration} at ${info.sampleRate} Hz, ${info.channels} ch');
```

It reports exactly what a full decode would, which the tests check against
`decodeAudio` for every fixture. Measured on a one-second stereo fixture,
warmed up and averaged (Apple M-series):

| Format | `audioInfo` | `decodeAudio` |
|---|---|---|
| Ogg Vorbis | 107 µs | 511 µs |
| MP3 | 0.9 µs | 217 µs |

The two formats differ because of what each has to do. Vorbis stores its
length in the container, so stb_vorbis opens the stream and reads it. MP3 has
no total-length field, so the frame headers still have to be walked; what is
skipped is the decoding and the PCM buffer, which is where the time goes.

## A note on MP3 length

MP3 is a lossy frame format with built-in encoder and decoder delay, so a
decoded MP3 is usually a little longer than the original audio, on the order of
a thousand samples per channel. Ogg Vorbis decodes to a length very close to
the source. If you need exact-length output, trim to the duration you expect.

## Feeding a speech model

Whisper, wav2vec 2.0 and the Vosk family all take the same input: **16 kHz
mono 16-bit PCM**. A decoded file is almost never that — 44.1 kHz stereo is the
normal case — so this is the step between the two.

```dart
final pcm = decodeAudio(File('interview.mp3').readAsBytesSync());
final input = toSpeechPcm(pcm);   // 16 kHz, mono
// input.samples is Int16List, ready for the model
```

`toSpeechPcm` is `resample(toMono(audio), 16000)`; both halves are public if
you want one without the other, and the rate is a parameter for a model that
wants 8 kHz.

Downsampling low-passes first, which is the part that is easy to skip and
expensive to skip. Going from 44.1 kHz to 16 kHz without a filter folds
everything above 8 kHz back into the band as a tone that was never recorded,
and nothing downstream can remove it. Measured: a 12 kHz tone resampled to
16 kHz comes back at 4 kHz with **under 5%** of its original energy — with the
filter removed, that alias is the loudest thing in the output. The test asserts
exactly that, so the filter cannot be quietly dropped.

`toMono` averages the channels rather than keeping one, so a stereo recording
with a speaker on each side does not lose half its content.

What this is not: a mastering-grade resampler. It is linear interpolation over
a filtered signal — right for speech features and analysis, which is what
callers do with PCM here. If you need a polyphase bank, this is not it.

## Performance, or: why not just run ffmpeg?

Shelling out to `ffmpeg` is the usual way to get PCM out of an encoded file
from Dart, and for an offline batch job it is a perfectly good answer. The
reason to decode in process is not that the codec here is faster. It is that
starting a process is not free, and you pay that cost once per file.

![Decoding the same Ogg file in process and by spawning ffmpeg. Every ffmpeg bar starts with the same 24.8 ms block of process startup, so at one second of audio almost none of the time is spent decoding](https://raw.githubusercontent.com/Yusufihsangorgel/audio_decode/main/doc/benchmark.png)

On an Apple M-series laptop, ffmpeg takes about 24.8 ms before it has decoded a
single sample. That figure is measured, not inferred: hand it a 0.05-second
clip, where there is essentially nothing to decode, and 24.8 ms is what is
left. It does not shrink for a short file, so decoding a one-second clip
through a subprocess spends 98% of its time not decoding.

The decoding itself is in the same class either way. Over thirty seconds of
audio ffmpeg spends about 15.7 ms on the samples, against 12.9 ms here. So the
difference is per file rather than per sample: a thousand short clips cost
about 25 seconds of process startup that in-process decoding never pays, while
one long file is close to a wash.

`dart run bench/vs_ffmpeg.dart` reproduces the chart on your machine. It checks
that both paths decode to the same samples before it reports any timing, so a
number that looks too good has to survive that first. `dart run bench/bench.dart`
measures absolute throughput instead: the 30-second stereo 44100 Hz clip above
is 2.6M interleaved samples, or about 205 million samples per second. These are
synthetic-tone numbers; a dense music track decodes more slowly.

## Platforms

The build hook compiles the vendored C with the toolchain that
`package:native_toolchain_c` drives (clang, gcc or MSVC). It targets the
platforms Dart's native build hooks support: Linux, macOS and Windows on the
Dart VM today, and Flutter as build-hook support there stabilises. Dart 3.10 or
newer is required.

## Credits and license

- stb_vorbis by Sean Barrett, public domain.
- minimp3 by lieff, public domain (CC0).

This package's own code is under the license in [LICENSE](LICENSE), which also
reproduces the upstream dedications for the vendored decoders.
