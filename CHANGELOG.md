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
