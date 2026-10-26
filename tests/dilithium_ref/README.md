# dilithium_ref: CRYSTALS-Dilithium (ML-DSA) reference implementation

Runs the upstream `test_dilithium.c` functional test on PULPissimo.

Source: https://github.com/pq-crystals/dilithium, folder `ref/`, commit
`d35ba3fe5449bee3e6d43e1f296c3ca818bd36be`. The clone in the repo root
(`/dilithium/`) is gitignored. The files needed here are copied into this
folder.

## Files

Copied unchanged from `ref/`:
`sign.c packing.c polyvec.c poly.c ntt.c reduce.c rounding.c fips202.c
symmetric-shake.c` and their headers, plus `config.h params.h api.h
symmetric.h randombytes.h`.

Changed:

| File | Change |
|------|--------|
| `test_dilithium.c` | From `ref/test/`. Include paths `../randombytes.h` and `../sign.h` changed to `randombytes.h` and `sign.h`. `#define NTESTS 10000` wrapped in `#ifndef NTESTS` so the iteration count can be set from `test.mk`. |
| `randombytes.c` | Replaced, identical to `kyber_ref/randombytes.c`. Upstream uses the OS (`getrandom`, `/dev/urandom`). This version is a deterministic xorshift32 PRNG with a fixed seed (`RANDOMBYTES_SEED`), so runs and cycle counts are reproducible. **Not cryptographically secure.** |

## Settings (`test.mk`)

| Variable | Default | Meaning |
|----------|---------|---------|
| `DILITHIUM_MODE` | `2` | `2` = Dilithium2, `3` = Dilithium3, `5` = Dilithium5 (upstream default: 2) |
| `NTESTS` | `1` | Iterations (upstream: 10000, far too slow for RTL simulation; one takes ~28 min here) |
| `STACK_SIZE` | `0x20000` | 128 KiB. Dilithium2 needs ~52 KiB in `dilithium_cycles`, plus ~11 KiB for the arrays `test_dilithium.c` keeps on the stack. |
| `TIMEOUT_US` | `4000000` | Simulated-time limit |

Override them on the command line, e.g.
`make run TEST=dilithium_ref DILITHIUM_MODE=3`. Objects are not rebuilt when
only flags change, so run `make clean-sw` first when switching
`DILITHIUM_MODE` or `NTESTS`.

The stack size was only measured for Dilithium2. Modes 3 and 5 use larger
matrices and need more stack. Run `dilithium_cycles` with the same mode
first: it reports peak usage and fails if the stack overflowed. This test
has no such check.

## Pass criteria

Per iteration, `test_dilithium.c`:
1. generates a key pair, signs a random 59-byte message with a 14-byte
   context, and verifies it,
2. checks the signed-message and message lengths and that the recovered
   message matches,
3. modifies one byte of the signed message and checks that verification
   now fails.

It prints the key and signature sizes and returns 0 on success.
