# audio_decode example

`audio_decode_example.dart` is a small command-line tool: give it an Ogg Vorbis
or MP3 file and it detects the format from the bytes, decodes to PCM, prints the
stream's shape and an ASCII waveform, and writes the samples back out as a WAV.

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

Run it against any Ogg or MP3 file:

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
wrote test/fixtures/sine_44100_mono_1s.ogg.wav (88244 bytes)
```

Invalid input does not produce garbage: `decodeAudio` throws an
`AudioDecodeException` the tool catches and reports.
