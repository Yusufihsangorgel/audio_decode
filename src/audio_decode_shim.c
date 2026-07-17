// C ABI shim over the vendored Ogg Vorbis decoder, Sean Barrett's stb_vorbis.
//
// This is the only translation unit that defines the stb_vorbis
// implementation, so it is compiled exactly once and nothing is generated at
// build time. The MP3 decoder lives in its own translation unit
// (audio_decode_mp3.c) because minimp3 and stb_vorbis each define file-local
// symbols with the same name (get_bits, and others); compiling both in one
// translation unit is a redefinition error, so they are kept apart.
//
// The exported entry points take plain pointers and a length, write the
// geometry through out-parameters, and hand back a heap buffer of interleaved
// 16-bit samples that the Dart side copies out and then releases with
// ad_free(). Failure is a non-zero return; no buffer is allocated on that path.

#if defined(_WIN32)
// Silence MSVC's warnings about "insecure" CRT functions so a warnings-as-
// errors build does not fail on the vendored C.
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif
#endif

#include <math.h>
#include <stdlib.h>
#include <string.h>

// stb_vorbis allocates a frame's scratch space with alloca(). It resolves
// alloca on its own for the common platforms, but include the right header
// explicitly so the declaration is always in scope: <malloc.h> on Windows,
// <alloca.h> on Linux. macOS/BSD declare alloca in <stdlib.h>, already above.
#if defined(_WIN32)
#include <malloc.h>
#elif defined(__linux__)
#include <alloca.h>
#endif

// Only the in-memory pull API is needed, so drop the stdio and push-data
// halves of stb_vorbis to keep the translation unit small.
#define STB_VORBIS_NO_STDIO
#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"

// MSVC exports nothing from a DLL by default, and CBuilder compiles the
// non-Windows targets with hidden visibility, so mark the C ABI entry points
// exported explicitly. stb_vorbis's own symbols stay internal to the library.
#if defined(_WIN32)
#define AD_EXPORT __declspec(dllexport)
#else
#define AD_EXPORT __attribute__((visibility("default")))
#endif

// Decodes a whole Ogg Vorbis stream from memory into interleaved int16 PCM.
//
// On success returns 0, writes the channel count, sample rate and per-channel
// sample count through the out-parameters, and stores a freshly malloc'd
// buffer of `channels * samplesPerChannel` int16 samples in `*out`. Returns a
// non-zero value on failure, in which case `*out` is left untouched. Free the
// result with ad_free().
AD_EXPORT int ad_decode_vorbis(const unsigned char* bytes, int len,
                               int* channels, int* rate,
                               int* samplesPerChannel, short** out) {
  int decoded_channels = 0;
  int decoded_rate = 0;
  short* output = NULL;
  int samples = stb_vorbis_decode_memory(bytes, len, &decoded_channels,
                                         &decoded_rate, &output);
  if (samples < 0 || output == NULL) {
    // stb_vorbis returns -1 on a corrupt or non-Vorbis stream. It never
    // allocates on that path, so there is nothing to free here.
    return 1;
  }
  *channels = decoded_channels;
  *rate = decoded_rate;
  *samplesPerChannel = samples;
  *out = output;
  return 0;
}

// Frees a buffer returned by ad_decode_vorbis() or ad_decode_mp3(). Both are
// plain malloc/realloc allocations from the same C runtime, so a single free()
// releases either one.
AD_EXPORT void ad_free(short* pointer) { free(pointer); }
