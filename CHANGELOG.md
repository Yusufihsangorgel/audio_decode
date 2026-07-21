## 0.3.0

- Add `PcmAudio.toFloat32()`, `PcmAudio.channel(int)` and `PcmAudio.toMono()`.
  The samples were only exposed as raw interleaved `Int16List`, so waveform,
  analysis and machine-learning callers all had to write the same
  divide-by-32768 loop and manual channel split. `toFloat32` returns the
  normalized `[-1.0, 1.0]` floats, `channel` deinterleaves one channel into a
  `Float32List`, and `toMono` averages the channels into a mono `PcmAudio`. All
  additive; existing fields and methods are unchanged.

## 0.2.3

- Widen the native-toolchain constraints so the package can be installed in a
  Flutter app at all. `hooks` 2.1.0 and `native_toolchain_c` 0.19.3 raised their
  `meta` floor to ^1.19.0, and Flutter's SDK pins `meta` to 1.17.0, so
  `flutter pub add` failed at version solving with "flutter from sdk is
  incompatible". Allowing `hooks >=2.0.2` and `native_toolchain_c >=0.19.2`
  lets the solver pick a version that works with the pinned `meta`, while a
  pure-Dart project still resolves to the newest. No API or behaviour change.

## 0.2.2

- Shorten the screenshot description. pub.dev accepts up to 200 characters but
  scores only those under 160, so the previous release published cleanly and
  quietly gave up the documentation points it was meant to earn.

## 0.2.1

- Declare the diagram in `pubspec.yaml` so pub.dev renders it on the package
  page. It was already in the repository and the README, but pub.dev shows only
  what the `screenshots:` field points at.

## 0.2.0

- Add `audioInfo`, `oggInfo` and `mp3Info`, which return an `AudioInfo` with
  `sampleRate`, `channels`, `frameCount` and `duration` without decoding to
  PCM. Reading a track's length used to mean decoding the whole file, which for
  four minutes of 44.1 kHz stereo materializes 40 MB of samples you then throw
  away. The new calls allocate no PCM: Vorbis answers from the container,
  and MP3 walks its frame headers with the decoder's synthesis step skipped.
  Measured on a one-second stereo fixture (Apple M-series, warmed up): Ogg
  107 µs against 511 µs for a full decode, MP3 0.9 µs against 217 µs. The
  reported geometry is checked against `decodeAudio` for every test fixture.

## 0.1.3

- Example: show what to do with the decoded PCM, not just how to re-encode it. It
  now reduces the samples to a one-line waveform (peak amplitude per column,
  scaled to the loudest column), the primitive a waveform view or a silence
  detector is built on.

## 0.1.2

- Docs: sharpen the pub.dev description to lead with the value and the terms people search.

## 0.1.1

- Move the stb_vorbis and minimp3 attributions out of `LICENSE` into
  `THIRD_PARTY_NOTICES.md`, so `LICENSE` is the plain MIT text that automated
  license detection recognises. The attributions themselves are unchanged and
  still ship with the package.

## 0.1.0

- Initial release.
- Ogg Vorbis decoding via stb_vorbis and MP3 decoding via minimp3, compiled
  from source with Dart build hooks.
- `decodeAudio`, `decodeOgg`, `decodeMp3`, `detectFormat` and `PcmAudio`.
- `encodeWav` writes decoded PCM to a 16-bit WAV.
