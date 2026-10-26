# kyber_ref: CRYSTALS-Kyber (ML-KEM) reference implementation

Runs the upstream `test_kyber.c` functional test on PULPissimo.

Source: https://github.com/pq-crystals/kyber, folder `ref/`, commit
`3edd5af5991927164edd4aacebfcbee00b8064e7`. The clone in the repo root
(`/kyber/`) is gitignored. The files needed here are copied into this folder.

## Files

Copied unchanged from `ref/`:
`kem.c indcpa.c polyvec.c poly.c ntt.c cbd.c reduce.c verify.c fips202.c
symmetric-shake.c` and their headers, plus `api.h params.h symmetric.h
randombytes.h`.

Changed:

| File | Change |
|------|--------|
| `test_kyber.c` | From `ref/test/`. Include paths `../kem.h` and `../randombytes.h` changed to `kem.h` and `randombytes.h`. `#define NTESTS 1000` wrapped in `#ifndef NTESTS` so the iteration count can be set from `test.mk`. |
| `randombytes.c` | Replaced. Upstream uses the OS (`getrandom`, `/dev/urandom`). This version is a deterministic xorshift32 PRNG with a fixed seed (`RANDOMBYTES_SEED`), so runs and cycle counts are reproducible. **Not cryptographically secure.** |

## Settings (`test.mk`)

| Variable | Default | Meaning |
|----------|---------|---------|
| `KYBER_K` | `3` | 2 = Kyber512, 3 = Kyber768, 4 = Kyber1024 |
| `NTESTS` | `1` | Iterations (upstream: 1000, far too slow for RTL simulation) |
| `STACK_SIZE` | `0x8000` | Kyber keeps keys and polynomial vectors on the stack. The runtime default of 2 KiB is not enough. |
| `TIMEOUT_US` | `2000000` | Simulated-time limit |

Override them on the command line, e.g. `make run TEST=kyber_ref KYBER_K=2`.
Objects are not rebuilt when only flags change, so run `make clean-sw` first
when switching `KYBER_K` or `NTESTS`.

## Pass criteria

Per iteration, `test_kyber.c` checks that:
1. both sides derive the same shared key,
2. decapsulating with a random secret key gives a different key,
3. decapsulating a modified ciphertext gives a different key.

It prints the key and ciphertext sizes and returns 0 on success.
