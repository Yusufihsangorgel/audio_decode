![audio_decode banner](https://raw.githubusercontent.com/Yusufihsangorgel/audio_decode/main/doc/banner.png)

# audio_decode

![Compressed bytes are decoded to PCM samples](https://raw.githubusercontent.com/Yusufihsangorgel/audio_decode/main/doc/architecture.png)

Native Ogg Vorbis and MP3 decoding to raw PCM for Dart, over FFI. The C
decoders are compiled from source by a Dart build hook, so the package is
self-contained: no platform plugins, no bundled binary, and no system library to
install beyond a C toolchain.

The same code path runs in pure Dart (command-line tools, servers, tests) and
in Flutter, and it decodes the same bytes to the same samples on every
platform. That makes it a good fit for waveform rendering, audio analysis,
resampling, machine-learning preprocessing, servers and games.

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

- Decodes Ogg Vorbis and MP3 to interleaved signed 16-bit PCM.
- Encodes PCM back to a 16-bit WAV file (`encodeWav`), so decoded audio can be
  saved or handed to other tools.
- No encoding to Vorbis or MP3, and no other container or codec.

## Quick start

```dart
import 'dart:io';
import 'package:audio_decode/audio_decode.dart';

void main() {
  final bytes = File('clip.mp3').readAsBytesSync();

  // Auto-detects Ogg Vorbis vs MP3 from the bytes.
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
Dart VM today, and Flutter as build-hook support there stabilises. Dart 3.9 or
newer is required.

## Credits and license

- stb_vorbis by Sean Barrett, public domain.
- minimp3 by lieff, public domain (CC0).

This package's own code is under the license in [LICENSE](LICENSE), which also
reproduces the upstream dedications for the vendored decoders.
