// Determinism probe: decode a fixture with the package's own C shims and
// print the geometry plus an FNV-1a hash of the interleaved samples.
// Compiled once per architecture; identical hashes across architectures are
// what the README's "same samples on every platform" claim requires.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ad_decode_vorbis(const unsigned char*, int, int*, int*, int*, short**);
int ad_decode_mp3(const unsigned char*, int, int*, int*, int*, short**);
void ad_free(short*);

static uint64_t fnv1a(const short* data, size_t n) {
  uint64_t h = 1469598103934665603ULL;
  const unsigned char* p = (const unsigned char*)data;
  for (size_t i = 0; i < n * sizeof(short); i++) {
    h ^= p[i];
    h *= 1099511628211ULL;
  }
  return h;
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: detdrv (ogg|mp3) file\n");
    return 2;
  }
  FILE* f = fopen(argv[2], "rb");
  if (!f) { perror("open"); return 2; }
  fseek(f, 0, SEEK_END);
  long len = ftell(f);
  fseek(f, 0, SEEK_SET);
  unsigned char* bytes = malloc((size_t)len);
  if (fread(bytes, 1, (size_t)len, f) != (size_t)len) { return 2; }
  fclose(f);

  int channels = 0, rate = 0, spc = 0;
  short* out = NULL;
  int rc = strcmp(argv[1], "ogg") == 0
      ? ad_decode_vorbis(bytes, (int)len, &channels, &rate, &spc, &out)
      : ad_decode_mp3(bytes, (int)len, &channels, &rate, &spc, &out);
  if (rc != 0) { fprintf(stderr, "decode failed\n"); return 1; }
  size_t total = (size_t)channels * (size_t)spc;
  printf("%s ch=%d rate=%d spc=%d fnv=%016llx\n", argv[2], channels, rate,
         spc, (unsigned long long)fnv1a(out, total));
  if (argc > 3) {
    FILE* o = fopen(argv[3], "wb");
    fwrite(out, sizeof(short), total, o);
    fclose(o);
  }
  ad_free(out);
  free(bytes);
  return 0;
}
