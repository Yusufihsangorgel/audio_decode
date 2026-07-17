import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the two C shims and the vendored single-file decoders into one
/// dynamic library at build time.
///
/// `src/audio_decode_shim.c` is the only translation unit that defines the
/// stb_vorbis implementation, and `src/audio_decode_mp3.c` is the only one that
/// defines the minimp3 implementation. They are separate translation units on
/// purpose: minimp3 and stb_vorbis each declare file-local symbols with the
/// same name (for example `get_bits`), so compiling both into a single
/// translation unit is a redefinition error. Nothing is generated at build
/// time.
///
/// The include roots are the vendored directory (so `#include "stb_vorbis.c"`
/// and `#include "minimp3.h"` resolve) and `src` itself. The library is
/// registered under the asset id of `lib/src/bindings.dart`, so the `@Native`
/// symbols in that file resolve to it.
void main(List<String> args) async {
  await build(args, (input, output) async {
    final targetOS = input.config.code.targetOS;

    final builder = CBuilder.library(
      name: 'audio_decode',
      assetName: 'src/bindings.dart',
      sources: ['src/audio_decode_shim.c', 'src/audio_decode_mp3.c'],
      includes: ['src/third_party', 'src'],
      defines: {
        // MSVC treats several CRT functions the decoders use as insecure and,
        // with warnings-as-errors, would fail the build.
        if (targetOS == OS.windows) '_CRT_SECURE_NO_WARNINGS': null,
        // Under glibc with a strict `-std=c11`, POSIX/GNU declarations such as
        // alloca (used by stb_vorbis) hide behind __STRICT_ANSI__. Requesting
        // the GNU feature set keeps them visible. It is a harmless no-op on
        // macOS and is never passed to MSVC.
        if (targetOS != OS.windows) '_GNU_SOURCE': null,
      },
      language: Language.c,
    );
    await builder.run(input: input, output: output);
  });
}
