/*
 * Replacement for the upstream ref/randombytes.c, which needs an OS (getrandom,
 * /dev/urandom). This is a deterministic xorshift32 PRNG with a fixed seed:
 * every run produces the same keys, which keeps simulation results and cycle
 * counts reproducible.
 *
 * NOT cryptographically secure. For testing only.
 */
#include <stddef.h>
#include <stdint.h>
#include "randombytes.h"

#ifndef RANDOMBYTES_SEED
#define RANDOMBYTES_SEED 0x2545F491u
#endif

static uint32_t state = RANDOMBYTES_SEED;

static uint32_t xorshift32(void)
{
  uint32_t x = state;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  state = x;
  return x;
}

void randombytes(uint8_t *out, size_t outlen)
{
  while(outlen > 0) {
    uint32_t r = xorshift32();
    for(int i = 0; i < 4 && outlen > 0; i++, outlen--) {
      *out++ = (uint8_t)r;
      r >>= 8;
    }
  }
}
