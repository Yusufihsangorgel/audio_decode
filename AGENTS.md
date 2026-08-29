# AGENTS.md

This package decodes MP3, Ogg Vorbis, and uncompressed WAV bytes to PCM. It cannot play audio: there is no device, stream, seek, or player, so a request to play a file is the wrong package.

## Scope

`decodeAudio` returns interleaved signed 16-bit PCM. It does not play, seek, stream, or encode to MP3 or Vorbis. `encodeWav` writes 16-bit PCM WAV only.

Decodes: Ogg Vorbis, MP3, uncompressed WAV (integer 8/16/24/32-bit and IEEE float 32/64). Does not decode AAC, FLAC, Opus, ADPCM, µ-law, or big-endian RIFX.

Native C via FFI (`hook/build.dart`). Dart VM on Linux, macOS, and Windows. Web is unsupported. `dart compile exe` does not ship the native library.

## Usage

Same calls as `example/audio_decode_example.dart`:

```dart
import 'dart:io';
import 'package:audio_decode/audio_decode.dart';

void main() {
  final bytes =
      File('test/fixtures/sine_44100_stereo_1s.ogg').readAsBytesSync();
  final pcm = decodeAudio(bytes);
  print('${pcm.sampleRate} Hz, ${pcm.channels} ch, ${pcm.duration}');
  File('clip.wav').writeAsBytesSync(encodeWav(pcm));
}
```

`decodeAudio` sniffs the format. Use `decodeOgg`, `decodeMp3`, or `decodeWav` when it is already known.

## Contracts

**PCM.** `PcmAudio.samples` is an `Int16List`: signed 16-bit, interleaved by channel (stereo is L, R, L, R). A frame is one sample per channel; `frameCount` is `samples.length ~/ channels`. Decode does not resample — a 48 kHz file stays 48 kHz. `toFloat32()` and `channel(int)` divide by 32768 into `[-1.0, 1.0]`.

**Truncated or malformed.** Empty bytes throw `ArgumentError`. Garbage and unrecognized formats throw `AudioDecodeException`. A cut inside the header throws. A cut after the header returns the frames that arrived and does not throw; an MP3 truncated to one third of the file decodes to roughly one third of the audio. A decode that yields no frames throws `AudioDecodeException`. Check `PcmAudio.duration` against what you expected; do not rely on an exception.

**Metadata without PCM.** `audioInfo` (or `oggInfo` / `mp3Info` / `wavInfo`) returns `AudioInfo` (`sampleRate`, `channels`, `frameCount`, `duration`) and allocates no sample buffer. Full decode of this repo's fixtures is 33–52× the file on disk as float32 (`samples.length * 4` in `example/info_without_decoding.dart`). Use `audioInfo` when you only need the shape.

**Native ownership.** `_decode` copies native int16 into a Dart `Int16List` and calls `adFree` before returning. Callers never see or free a native pointer.

## Easy mistakes

- **Using this to play sound.** Symptom: no player API, no audio device. Fix: this only returns PCM.
- **Treating `samples` as planar, or `samples.length` as a frame count.** Symptom: stereo at the wrong speed or with swapped channels. Fix: index `samples[frame * channels + ch]`; use `pcm.channel(i)` for one deinterleaved float channel.
- **Assuming decode outputs 16 kHz mono.** Symptom: a speech model receives 44100 Hz stereo. Fix: `toSpeechPcm(pcm)` (`resample(toMono(audio), 16000)`).
- **Expecting a truncated file to throw.** Symptom: a partial download is accepted. Fix: compare `duration` to the length you expected.
- **Decoding a whole file to read its length.** Symptom: 33–52× RAM versus disk on the fixtures (52× for `sine_44100_stereo_1s.ogg`). Fix: `audioInfo(bytes)`.
- **Downsampling by taking every Nth sample.** Symptom: a 12 kHz tone at 16 kHz aliases to 4 kHz (88.3% of source energy unfiltered vs 0.1% through `resample`). Fix: `resample`.
- **`dart compile exe`.** Symptom: `No asset with id 'package:audio_decode/src/bindings.dart'`. Fix: `dart build cli` and ship the whole `bundle/` directory.
- **Checksumming PCM across CPU architectures.** Symptom: hashes differ. Fix: about 0.03% of samples differ by one LSB between arm64 and x86-64; compare geometry.

## Layout

- `lib/audio_decode.dart` — public exports
- `lib/src/audio_decode_base.dart` — `decodeAudio`, `PcmAudio`, `audioInfo`, `encodeWav`
- `lib/src/wav_decoder.dart` — `decodeWav`, `wavInfo`
- `lib/src/resample.dart` — `resample`, `toMono`, `toSpeechPcm`
- `lib/src/bindings.dart` — `@Native` FFI (`ad_decode_vorbis`, `ad_decode_mp3`, `ad_free`)
- `hook/build.dart` — compiles `src/audio_decode_shim.c` and `src/audio_decode_mp3.c` as separate TUs (both define `get_bits`)
- `src/third_party/` — stb_vorbis, minimp3
- `example/` — decode, `audioInfo`, speech preprocessing
- `test/` — suite and `test/fixtures/`

`dart test` runs the suite and the build hook. `dart analyze`. SDK `^3.10.0`.
