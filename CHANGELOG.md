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
