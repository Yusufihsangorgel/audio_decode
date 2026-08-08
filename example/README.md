# audio_decode examples

Two command-line examples. Both run with no arguments against fixtures that
ship with the package, so you can see the output before finding an audio file
of your own.

| File | What it shows |
|---|---|
| `audio_decode_example.dart` | Decode any Ogg/MP3/WAV, inspect the stream, write it back as a WAV |
| `speech_input.dart` | Turn a decoded file into the 16 kHz mono PCM a speech model wants — and measure what skipping the filter would cost |

## `audio_decode_example.dart` — decode and inspect

Give it an Ogg Vorbis, MP3 or WAV file. It detects the format from the bytes,
decodes to PCM, prints the stream's shape and an ASCII waveform, and writes the
samples back out as a WAV.

```dart
final bytes = File(input).readAsBytesSync();
print('format: ${detectFormat(bytes).name}');   // detected from the bytes

final PcmAudio pcm = decodeAudio(bytes);         // throws AudioDecodeException on bad input
print('${pcm.sampleRate} Hz, ${pcm.channels}ch, ${pcm.frameCount} frames');

// Reduce the samples to a waveform: bucket frames into columns, take the peak
// in each — the primitive a waveform view or a silence detector is built on.
print(asciiWaveform(pcm));

File(output).writeAsBytesSync(encodeWav(pcm));
```

Run it against any Ogg, MP3 or WAV file:

```
dart run example/audio_decode_example.dart input.ogg [output.wav]
```

Against the one-second sine fixture in the repo:

```
$ dart run example/audio_decode_example.dart test/fixtures/sine_44100_mono_1s.ogg
format: ogg
sample rate: 44100 Hz
channels:    1
frames:      44100
duration:    0:00:01.000000
waveform:    ▇█▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇
wrote /tmp/audio_decode_example3YRMYt/sine_44100_mono_1s.ogg.wav (88244 bytes)
```

Give it a second argument and the WAV goes exactly there. Give it none, as above,
and it goes to a fresh directory under the system temp directory — never the
directory you ran from, so running the example in a checkout leaves nothing
behind in `git status`. The trailing characters after `audio_decode_example` are
random per run, and the transcript shortens macOS's real `/var/folders/…/T/`
prefix to `/tmp`; the path the example prints is the full one.

Invalid input does not produce garbage: `decodeAudio` throws an
`AudioDecodeException` the tool catches and reports.

## `speech_input.dart` — preprocessing for a speech model

Whisper, wav2vec 2.0 and the Vosk family want 16 kHz mono 16-bit PCM. A decoded
file is normally 44.1 kHz stereo. This example does that conversion with
`toSpeechPcm`, writes a WAV you can hand straight to a model, and then measures
the part of resampling that is easy to get wrong.

```
$ dart run example/speech_input.dart
decoded test/fixtures/sine_44100_stereo_1s.ogg
  before  44100 Hz  2 ch   44100 frames   88200 samples  0:00:01.000000
  after   16000 Hz  1 ch   16000 frames   16000 samples  0:00:01.000000
  5.5x fewer samples to push through the model
  wrote /tmp/audio_decode_speechJU7rAm/speech_input_16k_mono.wav (32044 bytes) — 16 kHz mono, feed this in

what the low-pass buys, measured on a 12 kHz tone
  at 16000 Hz that tone cannot exist, so it folds back to 4000 Hz
  resample()               0.1% of the source tone survives at 4000 Hz
  decimation, no filter   88.3% of the source tone survives at 4000 Hz
  the unfiltered run is the tone, intact, at a frequency nobody
  recorded — which is why resample() filters before it decimates.
```

The last block is the point of the example. Going from 44.1 kHz to 16 kHz
means discarding everything above 8 kHz, but only a filter actually discards
it. Plain decimation *moves* it: a 12 kHz tone reappears at 4 kHz, sounding
exactly like a tone that was really recorded there, and nothing downstream can
tell the two apart or remove it.

The example resamples the same tone both ways and reports the energy left at
4 kHz, so the difference is a number you measured rather than a claim you were
asked to believe. The figures above are from an Apple M-series laptop; the
package's test suite pins the filtered path at under 5%, and the run above
comes in at 0.1%.

Point it at your own audio, or ask for a different rate by editing the
`sampleRate` argument to `toSpeechPcm`:

```
dart run example/speech_input.dart interview.mp3 [model_input.wav]
```
