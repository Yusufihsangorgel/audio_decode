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
  `duration`.
- `decodeAudio(Uint8List)` sniffs the format and dispatches.
- `decodeOgg(Uint8List)` and `decodeMp3(Uint8List)` decode a known format.
- `detectFormat(Uint8List)` returns `AudioFormat.ogg`, `AudioFormat.mp3` or
  `AudioFormat.unknown`.
- `encodeWav(PcmAudio)` returns a canonical 16-bit PCM WAV as `Uint8List`.

Empty input throws `ArgumentError`. Bytes that are not decodable audio throw
`AudioDecodeException`.

Samples are copied out of native memory before each call returns, so there is
no native buffer for the caller to manage.

## A note on MP3 length

MP3 is a lossy frame format with built-in encoder and decoder delay, so a
decoded MP3 is usually a little longer than the original audio, on the order of
a thousand samples per channel. Ogg Vorbis decodes to a length very close to
the source. If you need exact-length output, trim to the duration you expect.

## Performance

Decoding runs entirely in native code. On an Apple M-series laptop, a
30-second stereo 44100 Hz Ogg Vorbis tone (2.6M interleaved samples) decodes in
about 12 ms median, roughly 215 million samples per second. Run
`dart run bench/bench.dart` to measure on your machine; it generates the clip
with ffmpeg if ffmpeg is installed and otherwise decodes the committed
one-second fixture. These are synthetic-tone numbers; a dense music track
decodes more slowly.

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
