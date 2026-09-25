# Package engineering rules: audio_decode

Rules-Version: audio_decode/6ff6674656d611121eb57624e402416ad8cce1ed33130fd17c249af666225bd3
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: 53aa3c6
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD 53aa3c6 (1.3.5). The API is synchronous and purely functional. FFI goes through a C shim. `lib/audio_decode.dart` consists only of `export ... show` lines. `lib/src/audio_decode_base.dart` keeps the value types (PcmAudio, AudioInfo, AudioFormat, AudioDecodeException), format sniffing, dispatch through an exhaustive switch, and the native decode/info path (`_decode`, `_info`) in one file. WAV decoding (`wav_decoder.dart`) and the DSP (`resample.dart`) are pure Dart. `bindings.dart` contains only `@Native` declarations. The hook builds two separate C translation units (`audio_decode_shim.c` + `audio_decode_mp3.c`, vendored stb_vorbis/minimp3). Native memory never reaches the caller. Samples are copied into an `Int16List` and freed with `adFree`. There is no streaming, cancellation, or isolate use. Structural flaws: an import cycle between base and wav_decoder and two separate public `toMono` functions.

## Layers and responsibilities
- lib/audio_decode.dart: Only the `export 'src/...' show` lists. This is the public API boundary (lines 38-53).
- lib/src/audio_decode_base.dart: Value types, `detectFormat`, `decodeAudio`/`audioInfo` dispatch, the `_decode`/`_info` FFI skeleton, and pure Dart `encodeWav`.
- lib/src/wav_decoder.dart: RIFF chunk walking, conversion of PCM and float samples to int16, and `wavInfo`.
- lib/src/resample.dart: `toMono`, `resample` with a windowed-sinc low-pass filter plus linear interpolation, and `toSpeechPcm`.
- lib/src/bindings.dart: 5 `@Native` symbols (ad_decode_vorbis, ad_decode_mp3, ad_info_vorbis, ad_info_mp3, ad_free). 0 means success. Results return through out-params.
- src/audio_decode_shim.c, src/audio_decode_mp3.c, src/third_party/: C ABI with `AD_EXPORT` macros. Vendored stb_vorbis and minimp3. Two separate TUs.
- hook/build.dart: Early return on `buildCodeAssets`, `CBuilder.library(assetName: 'src/bindings.dart')`, OS-dependent defines, and the `m` library.
- test/, test/fixtures/, example/, bench/: 7 test files and sine fixtures. 3 examples. A bench with an ffmpeg comparison.

## Public API and dependency direction
Functions: decodeAudio, decodeOgg, decodeMp3, decodeWav, detectFormat, audioInfo, oggInfo, mp3Info, wavInfo, encodeWav, resample, toMono, toSpeechPcm({sampleRate=16000}). Types: PcmAudio (sampleRate, channels, samples: Int16List, frameCount, duration, toFloat32, channel, toMono), AudioInfo (sampleRate, channels, frameCount, duration, ==/hashCode), AudioFormat {ogg, mp3, wav, unknown}, AudioDecodeException(message). All are synchronous. The boundary is the `show` lists at lib/audio_decode.dart:38-53. Two public surfaces share the name: the `PcmAudio.toMono()` method and the top-level `toMono(PcmAudio)` function.

lib/audio_decode.dart -> {audio_decode_base, resample, wav_decoder}. audio_decode_base -> bindings (FFI), wav_decoder (WAV dispatch), package:ffi. wav_decoder -> audio_decode_base (for types). This is a CYCLE (audio_decode_base.dart:4 <-> wav_decoder.dart:3). resample -> audio_decode_base (types only). bindings -> dart:ffi. hook -> hooks/code_assets/native_toolchain_c -> src/*.c. Native pointers live only inside audio_decode_base. If the cycle is broken, the direction is: types <- (native path | pure Dart decoder | DSP) <- entry.

## Error, state and platform contracts
- Error contract: malformed data -> `AudioDecodeException(message)` (final class, toString with a prefix). Empty input or parameter -> `ArgumentError.value(value, 'name', message)`. Channel index -> `RangeError.range` (audio_decode_base.dart:26-40, 100-103, 471-475; resample.dart:55-65).
- FFI call skeleton: the input is copied with `malloc` and out-params use `malloc<Int>()`. Everything is freed in a single try/finally. The native sample buffer is copied with `Int16List.fromList`, then `adFree` is called. Tracking of `nativeSamples` guarantees the free in the finally block when the copy fails (audio_decode_base.dart:381-440, 445-469).
- Format sniffing lives in one place, `detectFormat`. Dispatch is an exhaustive switch over `AudioFormat` with no default branch (audio_decode_base.dart:144-177, 215-227, 303-315).
- One-line public wrappers call a shared skeleton: decodeOgg/decodeMp3 -> `_decode`, oggInfo/mp3Info -> `_info` (audio_decode_base.dart:188-189, 204, 280, 291).
- Value types are `final class`. AudioInfo has value equality and a const constructor (audio_decode_base.dart:236-271).
- Pure Dart files never touch native code. The WAV chunk list is walked without assuming order. A zero-size loop is preserved (wav_decoder.dart:106-139).
- Dartdoc: every public member carries example code and a 'Throws ...' sentence (audio_decode_base.dart:179-189, 206-214).
- Hook pattern, shared with the C/C++ siblings: `if (!input.config.buildCodeAssets) return;`, OS-dependent defines and `libraries`, and a reason comment next to every flag (hook/build.dart:22-56).
- CHANGELOG entry: `## <version>` plus what changed, why it changed, and the test added (CHANGELOG.md:1-6).
- No mutable global state. The package level holds only `const _int16Scale` (audio_decode_base.dart:136).
- Documentation layout: AGENTS.md is written for package users (Scope/Usage/Contracts/Easy mistakes/Layout) and llms.txt exists.

## Package rules
### audio_decode/AD-01 [MUST]
The public API is exposed only through the `export 'src/...' show ...` lists in `lib/audio_decode.dart`. A new public symbol is added to that list by name; `lib/src` helpers (`_decode`, `_info`, bindings symbols) are not exported.
Reason: Do not produce a leaking public API; keep the breaking-change surface visible in a single file.
Evidence: lib/audio_decode.dart:38-53
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-02 [MUST]
`@Native` declarations live only in `lib/src/bindings.dart`; the hook registers that file with `assetName: 'src/bindings.dart'`. A new native symbol is added together: with `AD_EXPORT` in the shim, with a single `@Native` declaration in bindings, and in the AGENTS.md Layout list.
Reason: Symbol resolution is tied to a single file through the asset id; an `@Native` in another file does not resolve to this asset.
Evidence: lib/src/bindings.dart:3-6, 14-83; hook/build.dart:28-31; src/audio_decode_shim.c:48-50
Evidence role: current-pattern
Existing violation: audio_decode-D008

### audio_decode/AD-03 [MUST]
Every buffer passed to native code is allocated with `package:ffi` `malloc` and freed in a try/finally in the same function. The sample buffer returned by native code is first copied into a Dart `Int16List`, then released with `adFree`; if the copy throws, the finally block releases it. The caller never receives a native pointer.
Reason: The 'Native ownership' contract in AGENTS.md; native memory is invisible to the GC.
Evidence: lib/src/audio_decode_base.dart:381-440, 445-469; AGENTS.md:40
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-04 [MUST]
Error contract: corrupt or unrecognized data -> `AudioDecodeException`; empty input and invalid parameter -> `ArgumentError.value(value, 'name', message)`; channel index -> `RangeError`. A new error path introduces no new exception type.
Reason: The two classes the caller distinguishes (data error and programming error) must stay fixed.
Evidence: lib/src/audio_decode_base.dart:26-40, 100-103, 471-475; lib/src/resample.dart:55-65; lib/src/wav_decoder.dart:36-39, 92-98
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-05 [MUST]
A decode that yields zero frames throws `AudioDecodeException`; a file truncated after the header returns the frames that arrived and does not throw. A diff that touches this behavior updates test/truncation_test.dart and the AGENTS.md 'Truncated or malformed' paragraph in the same commit.
Reason: Documented and tested contract; if it drifts silently, the accept/reject behavior of partial downloads changes.
Evidence: lib/src/audio_decode_base.dart:406-419; AGENTS.md:36; test/truncation_test.dart:19
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-06 [MUST_NOT]
`wav_decoder.dart` and `resample.dart` do not depend on `dart:ffi` or `bindings.dart`. A new format or DSP operation that needs no native code is written in a pure Dart file.
Reason: WAV and encodeWav have no native code by design; pure Dart paths stay testable without a native library.
Evidence: lib/src/wav_decoder.dart:1-10; lib/src/resample.dart:1-4; lib/src/audio_decode_base.dart:320-322
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-07 [MUST]
Format sniffing happens only in `detectFormat`. `decodeAudio` and `audioInfo` dispatch through an exhaustive `switch` over `AudioFormat` with no default branch; a new enum value must break both switches with a compile error.
Reason: When a new format is added, the missing branch becomes visible to the compiler [internal mapping: J1, not moved to public text].
Evidence: lib/src/audio_decode_base.dart:12-24, 144-177, 215-227, 303-315
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-08 [MUST]
`hook/build.dart` keeps the `if (!input.config.buildCodeAssets) return;` line before any code config is read; `test/hook_test.dart` runs this path and is not deleted.
Reason: Bug fixed in 1.3.5: the hook threw in a build that requests no code assets.
Evidence: hook/build.dart:22-24; test/hook_test.dart:8-17; CHANGELOG.md:1-6
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-09 [MUST_NOT]
stb_vorbis and minimp3 are not compiled into the same translation unit; each implementation is defined only in its own shim file.
Reason: Two libraries define file-local symbols with the same name (`get_bits`); a single TU gives a redefinition error.
Evidence: hook/build.dart:8-14, 31
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-10 [SHOULD]
Vendored `src/third_party/` files are not edited in place; ABI and behavior adaptation happens in the shim, and provenance is kept in THIRD_PARTY_NOTICES.md.
Reason: Upstream updates must stay possible with the unpatched copy; the shim is the single adaptation point.
Evidence: hook/build.dart:5-19; THIRD_PARTY_NOTICES.md; src/third_party/
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-11 [MUST]
Public types are `final class`; value types compared by equality define `==` and `hashCode`. No mutable package-level state (top-level `var`, mutable static fields) is added, only `const`/`final`.
Reason: Prevent breakage through subclassing and shared-state races; the current code follows this.
Evidence: lib/src/audio_decode_base.dart:31, 49, 136, 236-266; lib/src/wav_decoder.dart:75
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-12 [MUST]
Every public declaration carries `///` and names the errors it throws with a 'Throws ...' sentence. The analyzer does not enforce this today; it is kept by hand.
Reason: The error contract is read from dartdoc; public_member_api_docs is off and no mechanical gate exists [internal mapping: D2].
Evidence: lib/src/audio_decode_base.dart:186-189, 202-204, 213-214, 278-280; analysis_options.yaml:1
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-13 [MUST]
A behavior change is written in CHANGELOG.md under a new `## <version>` heading: what changed, why, and which test was added. No behavior change is made without a test.
Reason: Repository pattern; every release entry names the test it adds.
Evidence: CHANGELOG.md:1-6; pubspec.yaml:6
Evidence role: current-pattern
Existing violation: none

### audio_decode/AD-14 [MUST]
A new native format is added in this order: `ad_decode_<x>`/`ad_info_<x>` with `AD_EXPORT` in the shim, the declaration in bindings.dart, an `AudioFormat` value, a `detectFormat` branch, a one-line public function calling the `_decode`/`_info` skeleton, the show list, and a test with fixtures. A second FFI call skeleton is not written.
Reason: This is the current extension point; a duplicated FFI skeleton produces debt.
Evidence: lib/src/audio_decode_base.dart:188-189, 204, 280, 291, 371-469
Evidence role: current-pattern
Existing violation: none

## Required verification
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed lib test bench example hook; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:24.
- Working directory: repository root; command: dart analyze --fatal-infos; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:25.
- Working directory: repository root; command: dart test; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:26.
Not verified by the survey:
- `dart analyze` and `dart test` were not run. `pub get` writes to .dart_tool, which is outside the read-only scope. The number of lints under strict analysis is unknown.
- The latest CI run result (no network).
- The C shim bodies were scanned only at the export-macro level (audio_decode_shim.c 113 lines, audio_decode_mp3.c 165 lines). The return-code and free contract was taken from comments in bindings.dart.
- `_info` (audio_decode_base.dart:445-469) does not reject zero geometry. `_decode` does reject it. The documentation does not state whether the difference is intentional. It was not measured by a test.
- Whether the images under doc/blog/ and `detdrv.c` enter the published archive (no `.pubignore`) was not measured. `dart pub publish --dry-run` was not run.
- Coverage and cognitive complexity scores were not measured.

## Existing debt
The complete register is docs/engineering/debt.json.
- audio_decode-D001 | small | lib/src/audio_decode_base.dart:118-131 <-> lib/src/resample.dart:11-36 | duplicated logic + double public API
  Fix: Delegate the method to the top-level function with `=> toMono(this)`; the public API is not removed. Make one decision for `channels < 1`, align both test groups to the same expectation, and record it in CHANGELOG.
  Closure: PcmAudio.toMono() delegates to the top-level toMono function and both paths enforce one shared behavior for channels below 1. test/audio_decode_test.dart and test/resample_test.dart assert the same expectation and CHANGELOG.md records the decision.
- audio_decode-D002 | medium | lib/src/audio_decode_base.dart:4 <-> lib/src/wav_decoder.dart:3 | import cycle / dependency direction
  Fix: Move the types and the exception to `lib/src/types.dart`; base, wav_decoder and resample import only that. Update the export lines in `lib/audio_decode.dart`; the names in the show lists and the public API do not change.
  Closure: PcmAudio, AudioInfo, AudioDecodeException and AudioFormat are defined in lib/src/types.dart and base, wav_decoder and resample import only that file for them. The show lists in lib/audio_decode.dart export the same names as before.
- audio_decode-D003 | small | lib/src/audio_decode_base.dart:74-76, 254-256 | duplicated logic
  Fix: A private `_durationOf(frameCount, sampleRate)` helper; both getters call it.
  Closure: Both duration getters call a single private _durationOf(frameCount, sampleRate) helper and the duplicated expression is gone.
- audio_decode-D004 | small | lib/src/resample.dart:33, 92-95, 163; lib/src/wav_decoder.dart:244-246 | repeated magic numbers
  Fix: Named int16 limit constants; one sentence of justification for the asymmetry, a fix and a round-trip test if it is not intentional.
  Closure: Named int16 limit constants replace the literals in all six places. The 32767 versus 32768 asymmetry carries a justification sentence or is fixed together with a round-trip test.
- audio_decode-D005 | small | lib/src/audio_decode_base.dart:369-381 | misplaced dartdoc
  Fix: Move the comment above `_decode` and write a short definition for the typedef.
  Closure: The shared decode path comment sits directly above _decode and typedef _DecodeFn carries its own short doc comment.
- audio_decode-D006 | small | lib/src/audio_decode_base.dart:1-8 | style inconsistency
  Fix: Order dart: -> package: -> relative; add the lint to analysis_options.
  Closure: Imports in lib/src/audio_decode_base.dart are ordered dart:, package: and relative, and directives_ordering is enabled in analysis_options.yaml.
- audio_decode-D007 | small | lib/src/audio_decode_base.dart:50-58 | unenforced precondition
  Fix: `assert(channels > 0 && samples.length % channels == 0)` (release behavior unchanged) + a debug test.
  Closure: The PcmAudio constructor asserts channels > 0 and samples.length % channels == 0. A debug test constructs an invalid PcmAudio and expects the assert to fire.
- audio_decode-D008 | small | AGENTS.md:59 <-> lib/src/bindings.dart:54-79 | documentation drift
  Fix: Complete the list.
  Closure: The AGENTS.md Layout list names ad_info_vorbis and ad_info_mp3 next to the other bindings symbols.
- audio_decode-D009 | small | pubspec.yaml (no top-level `platforms:`) | platform declaration
  Fix: Add `platforms: linux/macos/windows` in the same commit as the README.
  Closure: pubspec.yaml declares platforms: for linux, macos and windows and the README target list matches it.
- audio_decode-D010 | small | analysis_options.yaml:1 | analysis strictness
  Fix: Turn on the same settings and resolve the resulting diagnostics in the same PR.
  Closure: analysis_options.yaml enables strict-casts, strict-inference, strict-raw-types and public_member_api_docs and dart analyze reports no new diagnostics.
