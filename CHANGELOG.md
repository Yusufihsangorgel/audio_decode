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
