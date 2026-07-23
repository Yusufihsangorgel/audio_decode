## 0.5.0

Two things that had to be settled before a 1.0.0 freezes them.

- **Correct a false claim.** Every release up to 0.4.1 said this package
  "decodes the same bytes to the same samples on every platform", and the
  library documentation said it "decodes deterministically across platforms".
  That is not true, and it was never true. Compiling this package's own C for
  arm64 and for x86-64 with the same clang and the same flags and decoding the
  six test fixtures, five of them come out with different samples: about 0.03%
  of samples differ, always by one least-significant bit. Both decoders work in
  floating point and a compiler may fuse a multiply and an add on one
  architecture and not on another, which moves the last rounding. What is true,
  and is what the documentation now says, is that decoding is deterministic for
  a given build and that the reported geometry (channels, sample rate, frame
  count) matches everywhere. The practical consequence is narrow but real: a
  checksum of decoded PCM does not survive a move between architectures. The
  reason this went unnoticed is that the test suite runs on three operating
  systems but each runner only ever compares against itself.
- **Mark `PcmAudio`, `AudioInfo` and `AudioDecodeException` as `final`.** They
  are leaf types: none of them is designed to be extended or implemented, and
  nothing needs to. Sealing them now is what makes the rest of 1.x safe, since
  adding a method to an open class breaks anyone who implemented it, and
  `AudioInfo`'s `==` would otherwise be open to an asymmetric subclass. This is
  the breaking part of this release: `final` cannot be added after 1.0.0
  without a 2.0.0, while removing it later would not break anyone.

## 0.4.1

- Answer the question the README kept skipping: why decode in process rather
  than run `ffmpeg`. `bench/vs_ffmpeg.dart` measures both paths on the same
  file at four clip lengths, and the README now carries the result. The point
  is not that the codec is faster. Starting ffmpeg costs about 24.8 ms on an
  Apple M-series laptop before it decodes anything, measured by giving it a
  0.05-second clip where there is nothing to decode, and that cost is paid per
  file: at one second of audio, 98% of the subprocess time is not decoding. The
  decoding is in the same class either way, about 15.7 ms against 12.9 ms over
  thirty seconds.
- The bench compares the two decoders' output before it reports any timing, so
  a timing number cannot come from decoding less audio. Running it turned up
  one real difference, which it now reports rather than hiding: on a
  one-second clip ffmpeg's raw PCM pipe stops 128 frames early, while this
  package returns the full 44100 frames the container declares. The two agree
  exactly at five, fifteen and thirty seconds.

## 0.4.0

- Add value equality to `AudioInfo`. It now overrides `==` and `hashCode` over
  its `sampleRate`, `channels` and `frameCount` fields, so two values with the
  same geometry compare equal, share a `hashCode`, deduplicate in a `Set` and
  work as `Map` keys. This lands before the 1.0.0 freeze: giving a released
  value type value equality afterwards would change how existing `==`,
  `Set` and `Map` uses behave, which would be a breaking change. `PcmAudio`
  keeps identity equality by design, since its `samples` buffer is large and
  mutable and a structural `==` would scan every sample and rehash whenever the
  buffer is written. No existing fields or methods change.

## 0.3.2

- Fix the int32 overflow from 0.3.1 on the Ogg Vorbis path as well.
  `ad_info_vorbis` read the stream length from the final page's granule
  position as an `unsigned int` and narrowed it into the caller's `int` out
  parameter with no range check, so a stream whose granule passed 2^31 (about
  13.5 hours at 44.1 kHz) wrapped to a negative value that `oggInfo` and
  `audioInfo` surfaced as a negative `frameCount` and `duration` with no error.
  The Vorbis info path now rejects the overflow with an `AudioDecodeException`,
  the same guard the MP3 path already carried.

## 0.3.1

- Fix an int32 overflow: the MP3 decoder accumulated the per-channel sample
  count in a native `size_t` but narrowed it into the caller's `int` out
  parameter with no overflow check. A stream whose per-channel sample count
  passed 2^31 (about 13.5 hours at 44.1 kHz) wrapped to a negative value,
  which `mp3Info`/`audioInfo` surfaced as a negative `frameCount` and
  `duration` with no error, and which `decodeMp3` could turn into an unfreed
  native buffer surfaced as an unrelated `ArgumentError`. Both paths now
  reject the overflow explicitly (`AudioDecodeException`) instead of
  wrapping, and `_decode` frees the native buffer in a `finally` even if the
  copy into Dart memory throws.

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
