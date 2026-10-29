# Verilator test environment

Runs C programs on the full PULPissimo RTL with Verilator. Each test is a
folder of C/assembly sources, built with `sw/pulp-runtime`, so `printf()` works
and the return value of `main()` decides pass/fail.

## Requirements

- Verilator 5.x (needs `--timing`)
- A `riscv32-unknown-elf-gcc` on `PATH`. A stock GCC works; the PULP GCC fork
  is not needed.
- `python3`
- Dependencies checked out: `make checkout` in the repo root (run
  automatically on first use).

## Usage

```sh
cd tests
make                        # list tests and options
make run TEST=hello         # build + simulate one test
make all-tests              # run every test, print a summary, non-zero exit on failure
make run TEST=hello WAVES=1 # also dump build/sw-<core>/hello/waves.fst
make run TEST=hello CORE=ibex
```

The first `run` verilates the SoC (about 1.5 min). After that the model is
rebuilt only when the environment files change. It is **not** rebuilt when
you edit the SoC's RTL (`hw/`, `.bender/`): run `make clean` after any
hardware change, otherwise the old model is used.

Example output:

```
[TB] Loaded 903 words from .../hello.mem, entry point 0x1c008080
[TB] 152.581 us: Reset released
[STDOUT-CL31_PE0, 167.370 us] Hello from PULPissimo!
[TB] 168.170 us: PASSED (exit code 0)
```

Options:

| Variable     | Default    | Meaning                                         |
|--------------|------------|-------------------------------------------------|
| `CORE`       | `cv32e40p` | `cv32e40p` (with FPU) or `ibex` (RV32IMC)       |
| `TIMEOUT_US` | `100000`   | Simulated time after which the test fails       |
| `WAVES`      | `0`        | `1` dumps an FST waveform                       |
| `SW_VERBOSE` | `0`        | `1` shows the full compiler command lines       |

## Tests

| Test | What it does | Wall time (CV32E40P) |
|------|--------------|----------------------|
| `hello` | Prints a line and exits | ~2 s |
| `l2_preload` | Checks that a 96 KiB table loaded into all L2 regions reads back correctly | ~15 s |
| `cycle_count` | Example of timing one function call with `cycles.h` | ~2 s |
| `kyber_ref` | Upstream Kyber functional test (`test_kyber.c`), see [Kyber](#kyber-ml-kem) | ~13 min |
| `kyber_cycles` | Cycle counts of Kyber keypair / encapsulation / decapsulation | ~4.5 min per iteration (`NTESTS`) |
| `dilithium_ref` | Upstream Dilithium functional test (`test_dilithium.c`), see [Dilithium](#dilithium-ml-dsa) | ~28 min |
| `dilithium_cycles` | Cycle counts of Dilithium keypair / sign / verify, plus peak stack usage | ~25 min (Dilithium2), ~40 min (Dilithium5) per iteration (`NTESTS`) |

Ibex takes about 1.5–2x longer in wall time. `make all-tests` runs
everything, so expect it to take **well over an hour** because of the PQC
tests. To run only specific tests, call `make run TEST=...` for each, in
parallel shells if you like (each simulation uses one CPU core).

## Adding a test

Create a folder with at least one `.c` or `.S` file:

```
tests/my_test/my_test.c
```

```c
#include <stdio.h>

int main(void)
{
    printf("hi\n");
    return 0; // 0 = PASS, anything else = FAIL
}
```

`make run TEST=my_test` builds every `.c`/`.S` file in the folder. For extra
flags or sources, add an optional `test.mk` in the folder:

```make
PULP_APP_CFLAGS += -DMY_DEFINE=1
PULP_APP_SRCS   += ../common/helpers.c
STACK_SIZE = 0x4000        # bytes, default 0x800 (2 KiB)
TIMEOUT_US = 1000000       # this test's default simulation timeout
```

| `test.mk` variable | Default | Meaning |
|--------------------|---------|---------|
| `PULP_APP_CFLAGS`, `PULP_APP_SRCS` | | Extra compiler flags / extra source files (paths relative to the test folder) |
| `STACK_SIZE` | `0x800` | Stack size in bytes. The runtime's default is only 2 KiB, and **overflowing it is silent** (it corrupts other memory), so raise it for code with large local arrays. |
| `TIMEOUT_US` | `100000` | Default timeout for this test. A `TIMEOUT_US=` on the command line still wins. |
| `SW_VARIANT` | | Suffix for the test's build directory, e.g. `SW_VARIANT = k$(KYBER_K)` builds into `build/sw-<core>/<test>-k3/`. Give every configuration flag a place in it. |

Objects are rebuilt when sources change, not when flags do. For a
configuration variable on the command line (like `KYBER_K`), add it to
`SW_VARIANT` so each value gets its own build directory. That way switching
needs no clean, and several configurations can run in parallel. Otherwise,
run `make clean-sw` after changing flags.

pulp-runtime headers (`pulp.h`, HAL, drivers) are on the include path. See
`sw/pulp-runtime` and `sw/regression_tests` for examples of peripheral access.
`memcmp`, `memcpy`, `memset`, `memmove`, `snprintf` and `fprintf` are
available (`stdout` and `stderr` both print to the same output).

## Measuring cycles

`env/include/cycles.h` is on every test's include path. It reads the
standard `mcycle` counter, so the counts work on both cores and match real
hardware, as long as nothing prints inside the measured region.

```c
#include "cycles.h"

cycles_enable();                       // required: CV32E40P resets with the counter off
uint64_t overhead = cycles_overhead(); // cost of the reads themselves
uint64_t t0 = cycles_read();
my_function();
uint64_t n = cycles_read() - t0 - overhead;
cycles_print("my_function", n);        // print only after measuring
```

`tests/cycle_count/` is a complete example. Mark the measured function
`__attribute__((noinline))` so it stays a real call. The minimal `printf` has
no `%llu`, so use `cycles_print()` for 64-bit counts.

| Function | Purpose |
|----------|---------|
| `cycles_enable()` | Start the counter. Call once before measuring. CV32E40P resets with it **off**, so without this every count is 0. |
| `cycles_read()` | Current 64-bit cycle count |
| `cycles_overhead()` | Cycles taken by the reads themselves (CV32E40P: 13, Ibex: 4). Subtract it from each measurement. |
| `cycles_print(label, n)` | Prints `label: n cycles` |
| `cycles_print_stats(label, c, n)` | Prints min, median and max of the `n` counts in `c` (sorts `c`) |

Counts are in SoC clock cycles: 50 MHz in this simulator, 10 MHz on the
Nexys FPGA targets. They are identical between simulation and hardware for
code that only uses the core and memory.

## Measuring stack usage

`env/include/stack.h` measures peak stack usage by filling the free stack
with a pattern and checking later how much of it was overwritten:

```c
#include "stack.h"

stack_paint();                   // before the code; not inside a cycle measurement
my_function();
printf("peak stack: %u of %u bytes\n",
       (unsigned)stack_max_used(), (unsigned)stack_size());
if (stack_overflowed())          // STACK_SIZE in test.mk is too small
    return 1;
```

The result includes `main()`'s own frame. Use it to choose `STACK_SIZE` for
a test. `dilithium_cycles` is an example.

## Kyber (ML-KEM)

Two tests run the CRYSTALS-Kyber reference implementation
([pq-crystals/kyber](https://github.com/pq-crystals/kyber), folder `ref/`):

| Test | Purpose |
|------|---------|
| `kyber_ref` | Upstream functional test: shared keys match, and a wrong secret key or modified ciphertext gives a different key |
| `kyber_cycles` | Measures `crypto_kem_keypair`, `crypto_kem_enc` and `crypto_kem_dec` separately and prints the cycle counts and peak stack usage |

The Kyber code exists once, in `kyber_ref/`. `kyber_cycles` compiles it from
there through its `test.mk`. What was copied and changed is listed in
[kyber_ref/README.md](kyber_ref/README.md). In short, `randombytes()` is
replaced by a **fixed-seed pseudorandom generator**, so every run produces
the same keys and the same cycle counts. It is not secure; use it for
testing only.

```sh
make run TEST=kyber_cycles             # Kyber768 on CV32E40P, ~4.5 min
make run TEST=kyber_cycles CORE=ibex   # ~7.5 min
make run TEST=kyber_ref                # functional test, ~13 min
```

Example output of `kyber_cycles`:

```
[STDOUT-CL31_PE0, 105682.390 us] Kyber768
[STDOUT-CL31_PE0, 105727.410 us] crypto_kem_keypair: 1525556 cycles
[STDOUT-CL31_PE0, 105772.550 us] crypto_kem_enc    : 1741674 cycles
[STDOUT-CL31_PE0, 105817.670 us] crypto_kem_dec    : 1959668 cycles
[STDOUT-CL31_PE0, 105867.010 us] measurement overhead (subtracted): 13 cycles
[STDOUT-CL31_PE0, 106544.610 us] peak stack usage: 14804 of 32768 bytes
[STDOUT-CL31_PE0, 106556.250 us] shared keys match
[TB] 106557.470 us: PASSED (exit code 0)
```

The test fails if the two shared keys differ or the stack overflowed, so a printed count always
belongs to a correct run.

### Options

| Variable | Default | Tests | Meaning |
|----------|---------|-------|---------|
| `KYBER_K` | `3` | both | Parameter set: `2` = Kyber512, `3` = Kyber768, `4` = Kyber1024 |
| `NTESTS` | `1` | both | Iterations. `kyber_ref`: of the three checks (upstream uses 1000; each takes ~13 min here). `kyber_cycles`: of the three measurements, each with new keys (see below). |
| `CORE` | `cv32e40p` | both | `cv32e40p` or `ibex` |

Kyber needs a 32 KiB stack (`STACK_SIZE = 0x8000` in both `test.mk` files),
and its timeout is 2 s of simulated time (`kyber_cycles`: per iteration). Larger parameter sets take
proportionally longer; if a run hits the timeout, add `TIMEOUT_US=5000000`.

Each setting builds into its own directory
(`build/sw-<core>/kyber_cycles-k2/`, `kyber_cycles-k2-n5/`, `kyber_ref-k3-n1/`, ...), so you can
switch without cleaning and run several in parallel shells:

```sh
make run TEST=kyber_cycles KYBER_K=2   # Kyber512
make run TEST=kyber_cycles KYBER_K=4   # Kyber1024
```

`kyber_cycles` also prints peak stack usage and fails if the stack
overflowed.

### Several iterations (`NTESTS`)

`make run TEST=kyber_cycles NTESTS=5` repeats keypair / enc / dec five
times. Each iteration continues the pseudorandom stream, so it gets new keys
and new encapsulation randomness, the same as a different seed. Iteration 1
uses the fixed seed of an `NTESTS=1` run. The test prints the counts of each
iteration, then min, median and max:

```
Kyber512
iteration 1
crypto_kem_keypair: 926554 cycles
...
iteration 5
...
over 5 iterations
crypto_kem_keypair: min 926184, median 926554, max 948783 cycles
crypto_kem_enc    : min 1068216, median 1068586, max 1090817 cycles
crypto_kem_dec    : min 1238771, median 1239141, max 1261369 cycles
```

The test fails if the shared keys differ in any iteration.
`env/cycles_table.py` turns the logs into the results table below:

```sh
python3 env/cycles_table.py build/sw-*/kyber_cycles-k*-n5/sim.log
```

### Results (`-O2`, all parameter sets, `NTESTS=5`)

Cycles. **1 seed** is iteration 1 (the fixed seed); median and min – max are
over the 5 iterations:

| Parameter set | Operation | CV32E40P 1 seed | median | min – max | Ibex 1 seed | median | min – max |
|---|---|---:|---:|---:|---:|---:|---:|
| Kyber512 (n = 5) | `crypto_kem_keypair` | 926,554 | 926,554 | 926,184 – 948,783 | 1,276,851 | 1,276,851 | 1,276,431 – 1,309,431 |
|  | `crypto_kem_enc` | 1,068,586 | 1,068,586 | 1,068,216 – 1,090,817 | 1,452,007 | 1,452,007 | 1,451,586 – 1,484,586 |
|  | `crypto_kem_dec` | 1,239,141 | 1,239,141 | 1,238,771 – 1,261,369 | 1,707,845 | 1,707,845 | 1,707,424 – 1,740,424 |
| Kyber768 (n = 5) | `crypto_kem_keypair` | 1,525,614 | 1,526,011 | 1,525,231 – 1,526,232 | 2,102,266 | 2,102,725 | 2,101,854 – 2,102,907 |
|  | `crypto_kem_enc` | 1,741,732 | 1,742,133 | 1,741,353 – 1,742,351 | 2,388,120 | 2,388,578 | 2,387,707 – 2,388,760 |
|  | `crypto_kem_dec` | 1,959,706 | 1,960,106 | 1,959,327 – 1,960,320 | 2,725,040 | 2,725,498 | 2,724,627 – 2,725,680 |
| Kyber1024 (n = 5) | `crypto_kem_keypair` | 2,386,803 | 2,387,592 | 2,386,654 – 2,409,207 | 3,306,151 | 3,306,950 | 3,305,971 – 3,338,955 |
|  | `crypto_kem_enc` | 2,637,400 | 2,638,184 | 2,637,247 – 2,659,801 | 3,650,072 | 3,650,870 | 3,649,891 – 3,682,875 |
|  | `crypto_kem_dec` | 2,913,431 | 2,914,217 | 2,913,282 – 2,935,833 | 4,074,617 | 4,075,415 | 4,074,436 – 4,107,420 |

Median time at 10 MHz (the SoC clock of the Nexys FPGA targets) and peak stack:

| Parameter set | Operation | CV32E40P | Ibex | Peak stack (both cores) |
|---------------|-----------|---------:|-----:|------------------------:|
| Kyber512 | keypair / enc / dec | 92.7 / 106.9 / 123.9 ms | 127.7 / 145.2 / 170.8 ms | 9,956 B |
| Kyber768 | keypair / enc / dec | 152.6 / 174.2 / 196.0 ms | 210.3 / 238.9 / 272.5 ms | 14,852 B |
| Kyber1024 | keypair / enc / dec | 238.8 / 263.8 / 291.4 ms | 330.7 / 365.1 / 407.5 ms | 20,964 B |

- All parameter sets fit in the 32 KiB stack (`STACK_SIZE = 0x8000`).
- **The seed matters little.** Most iterations are within 0.05% of each
  other. The exception is the public matrix, which Kyber generates by
  rejection sampling: now and then a seed needs one more SHAKE128 block.
  Encapsulation and decapsulation regenerate the matrix, so all three
  operations of that iteration cost more. Kyber512 and Kyber1024 each had
  one such seed among the 5: about +22,500 cycles on CV32E40P and +33,000
  on Ibex per operation (up to 2.6%).
- **Code layout shifts counts slightly** (~0.01%) when code or data moves in
  memory, through instruction and data alignment. Adding the stack report
  to `kyber_cycles.c` changed Kyber768 keypair from 1,525,439 to 1,525,556
  cycles; the `NTESTS` loop changed it to 1,525,614 (iteration 1, same
  seed). Compare configurations built from the same code.
- Both cores run plain RV32IM(F)C code: stock GCC can't generate CV32E40P's
  PULP instructions. Keep this in mind when comparing with published
  figures.

### Timing other Kyber functions

To time internal functions (e.g. `poly_ntt`, `indcpa_keypair_derand`), add
measurements to `kyber_cycles/kyber_cycles.c` the same way. Include the
function's header (`#include "poly.h"`, `"indcpa.h"`, ...) and call it
between two `cycles_read()` calls. The headers map names to Kyber's
namespaced symbols, so the plain names work. Print only after all
measurements are done.

## Dilithium (ML-DSA)

Two tests run the CRYSTALS-Dilithium reference implementation
([pq-crystals/dilithium](https://github.com/pq-crystals/dilithium), folder
`ref/`), set up the same way as Kyber:

| Test | Purpose |
|------|---------|
| `dilithium_ref` | Upstream functional test: sign and verify a message, check lengths and message, and check that a modified signed message fails verification |
| `dilithium_cycles` | Measures `crypto_sign_keypair`, `crypto_sign` and `crypto_sign_open` separately, prints the cycle counts and peak stack usage |

The Dilithium code exists once, in `dilithium_ref/`, and `dilithium_cycles`
compiles it from there. Changes are listed in
[dilithium_ref/README.md](dilithium_ref/README.md). `randombytes()` is the
same fixed-seed generator as for Kyber (not secure; testing only). The
message (59 bytes) and context (14 bytes) match the upstream test.

```sh
make run TEST=dilithium_cycles             # Dilithium2 on CV32E40P, ~25 min
make run TEST=dilithium_cycles CORE=ibex   # ~39 min
make run TEST=dilithium_ref                # functional test, ~28 min
```

Example output of `dilithium_cycles`:

```
[STDOUT-CL31_PE0, 585295.830 us] Dilithium2
[STDOUT-CL31_PE0, 585340.330 us] crypto_sign_keypair: 3307132 cycles
[STDOUT-CL31_PE0, 585385.650 us] crypto_sign        : 22185892 cycles
[STDOUT-CL31_PE0, 585430.230 us] crypto_sign_open   : 3582361 cycles
[STDOUT-CL31_PE0, 585478.090 us] measurement overhead (subtracted): 13 cycles
[STDOUT-CL31_PE0, 588289.750 us] peak stack usage: 52692 of 131072 bytes
[STDOUT-CL31_PE0, 588305.990 us] signature verified
[TB] 588307.070 us: PASSED (exit code 0)
```

The test fails if verification fails or the stack overflowed, so a printed
count always belongs to a correct run.

### Options

| Variable | Default | Tests | Meaning |
|----------|---------|-------|---------|
| `DILITHIUM_MODE` | `2` | both | Parameter set: `2` = Dilithium2, `3` = Dilithium3, `5` = Dilithium5 |
| `NTESTS` | `1` | both | Iterations. `dilithium_ref`: upstream uses 10000; each takes ~28 min here. `dilithium_cycles`: of the three measurements, each with a new message, keys and signing randomness (as for Kyber). |
| `CORE` | `cv32e40p` | both | `cv32e40p` or `ibex` |

The stack size depends on the mode: 128 KiB (`0x20000`) for Dilithium2 and
192 KiB (`0x30000`) for Dilithium3/5, set in `test.mk`. Peak use measured by
`dilithium_cycles` is 52.7 / 80.3 / 123.3 KiB (see the results below), so
both tests have room to spare, including the ~11 KiB of extra arrays that
`test_dilithium.c` keeps on its stack. The simulated-time limit is 8 s per
iteration (Dilithium5 on Ibex needs ~1.2 s for the fixed seed; the slowest
of the 5 seeds below, Dilithium3 on Ibex, ~1.9 s).

Each setting builds into its own directory (e.g.
`build/sw-<core>/dilithium_cycles-mode3/`), so no clean is needed when
switching:

```sh
make run TEST=dilithium_cycles DILITHIUM_MODE=3
make run TEST=dilithium_cycles DILITHIUM_MODE=3 NTESTS=5   # build/sw-<core>/dilithium_cycles-mode3-n5/
```

`NTESTS` works as for `kyber_cycles`: iteration 1 is the fixed seed, then
min, median and max are printed, and `env/cycles_table.py` makes the table.

### Results (`-O2`, all parameter sets, `NTESTS=5`)

Cycles. **1 seed** is iteration 1 (the fixed seed); median and min – max are
over the 5 iterations:

| Parameter set | Operation | CV32E40P 1 seed | median | min – max | Ibex 1 seed | median | min – max |
|---|---|---:|---:|---:|---:|---:|---:|
| Dilithium2 (n = 5) | `crypto_sign_keypair` | 3,335,297 | 3,357,863 | 3,335,297 – 3,357,970 | 4,474,813 | 4,507,039 | 4,474,813 – 4,507,174 |
|  | `crypto_sign` | 22,485,241 | 14,125,617 | 5,420,911 – 22,485,241 | 27,942,795 | 17,629,262 | 6,915,398 – 27,942,795 |
|  | `crypto_sign_open` | 3,617,716 | 3,618,002 | 3,617,716 – 3,618,234 | 4,775,118 | 4,775,441 | 4,775,118 – 4,775,722 |
| Dilithium3 (n = 5) | `crypto_sign_keypair` | 5,837,096 | 5,838,147 | 5,836,952 – 5,838,520 | 7,895,178 | 7,896,285 | 7,895,068 – 7,896,707 |
|  | `crypto_sign` | 23,598,885 | 25,053,918 | 13,928,560 – 63,402,423 | 29,348,490 | 31,215,653 | 17,587,171 – 78,232,370 |
|  | `crypto_sign_open` | 5,978,366 | 5,978,569 | 5,978,205 – 5,978,663 | 7,959,930 | 7,960,159 | 7,959,753 – 7,960,263 |
| Dilithium5 (n = 5) | `crypto_sign_keypair` | 9,835,904 | 9,835,904 | 9,700,649 – 9,858,772 | 13,359,105 | 13,359,105 | 13,165,893 – 13,391,654 |
|  | `crypto_sign` | 25,018,373 | 13,386,470 | 13,386,228 – 38,059,527 | 31,660,482 | 17,436,086 | 17,435,821 – 47,521,302 |
|  | `crypto_sign_open` | 10,113,046 | 10,112,918 | 10,112,788 – 10,113,046 | 13,571,129 | 13,570,989 | 13,570,853 – 13,571,129 |

Median time at 10 MHz (the SoC clock of the Nexys FPGA targets) and peak stack:

| Parameter set | Operation | CV32E40P | Ibex | Peak stack (both cores) |
|---------------|-----------|---------:|-----:|------------------------:|
| Dilithium2 | keypair / sign / open | 335.8 / 1,412.6 / 361.8 ms | 450.7 / 1,762.9 / 477.5 ms | 52,724 of 131,072 B |
| Dilithium3 | keypair / sign / open | 583.8 / 2,505.4 / 597.9 ms | 789.6 / 3,121.6 / 796.0 ms | 80,372 of 196,608 B |
| Dilithium5 | keypair / sign / open | 983.6 / 1,338.6 / 1,011.3 ms | 1,335.9 / 1,743.6 / 1,357.1 ms | 123,364 of 196,608 B |

**Signing time varies with the input.** Dilithium signing repeats an inner
loop until a candidate signature passes its checks (rejection sampling), and
the number of repetitions depends on the key, message and randomness. Over
the 5 seeds, signing varies by a factor of 2.8 to 4.6 (Dilithium2 on
CV32E40P: 5.4 to 22.5 million cycles). The fixed seed happens to be a slow
one for Dilithium2 and Dilithium5. Key generation varies by up to ~1.7%
(rejection sampling while expanding the matrix and the secret vectors),
verification by ~0.01%.

Five samples are still few for signing: the median can move a lot with
more seeds, so don't compare signing cost between modes from these
numbers. Published benchmarks usually report the median over hundreds or
thousands of runs; raise `NTESTS` for that (each Dilithium iteration takes
~25 to 70 min of simulation).

The fixed-seed counts (1 seed) differ from earlier `NTESTS=1` runs by up to
1.4% on CV32E40P (Dilithium2 keypair: 3,307,132 then, 3,335,297 now), with
the same inputs. The `NTESTS` loop moved the Dilithium code by 0x422 bytes,
not a multiple of 4, so every hot function changed its 4-byte alignment.
CV32E40P is sensitive to that (a 32-bit instruction that spans two words
takes an extra fetch). On Ibex the difference is at most 0.2%; for Kyber
the code moved by a multiple of 4 and the counts changed by ~0.005%.

## FPGA area

`fpga/` synthesizes PULPissimo for the Nexys 4 DDR (XC7A100T) with Vivado and
reports LUTs, FFs, BRAM and DSPs for the core, the FPU and each SoC block:

```sh
cd fpga
make area              # CV32E40P with FPU, post-opt_design, ~9 min
make area CORE=ibex
make compare IMPL=1    # both cores, post-route, ~13 min each
```

Post-route:

| | CV32E40P | Ibex |
|---|---:|---:|
| Whole design (LUTs / FFs / BRAM / DSPs) | 41,343 / 22,339 / 82 / 12 | 33,463 / 20,684 / 82 / 4 |
| Core | 7,302 / 2,660 / 0 / 7 | 3,181 / 1,387 / 0 / 1 |
| FPU | 3,666 / 382 / 0 / 2 | – |
| SoC without core and FPU | 30,375 / 19,297 / 82 / 3 | 30,282 / 19,297 / 82 / 3 |

Setup timing is met at the Nexys clocks (10 MHz SoC); hold is not, because
of upstream's LUT-based clock gating (details in the FPGA README).

Details, options and how it differs from the upstream FPGA flow:
[fpga/README.md](fpga/README.md).

## Outputs

`build/sw-<core>/<test>/` (or `<test>-<SW_VARIANT>/`) holds the ELF, the
disassembly (`<test>.dis`), the memory image, `sim.log` and the optional
`waves.fst`.
`build/sim-<core>/` holds the Verilator model, `build/fpga/` the FPGA area builds.

## How it works

The repo officially supports only Questa and Xcelium. This environment adds
Verilator support without changing any tracked files:

| File                            | Purpose |
|---------------------------------|---------|
| `env/tb_verilator.sv`           | Testbench. Backdoor-loads the program into the L2 SRAM models during reset, sets the FC boot address to the ELF entry point, then waits for the program to write `CORESTATUS` (which `exit()`/return from `main` does). Replaces the JTAG boot of `target/sim/tb`, whose packages need simulator features Verilator lacks. |
| `env/clock_gen_verilator.sv`    | Replaces `hw/clock_gen_generic.sv`. The FLL model is VHDL, so this module generates fixed ~50 MHz SoC/peripheral clocks instead and backs the FLL config registers with a stub, so the runtime's FLL setup works. |
| `env/pad_functional_verilator.sv` | Replaces the pad cells in `tech_cells_generic`, which use switch primitives (`rpmos`) that Verilator doesn't support. |
| `env/elf2mem.py`                | Converts the ELF to the `addr data` image the TB loads. |
| `env/sw.mk`                     | Builds a test with pulp-runtime, using compiler flags that work with stock GCC (see the comments in the file). |

Workarounds applied by the Makefile (originals untouched):

- `bender script verilator` is called with `--no-default-target`. Otherwise
  it implies the `synthesis` target, which drops the simulation-only
  virtual stdout (`tb_fs_handler`).
- `adv_dbg_if` is excluded from bender and its files are listed by hand,
  because its `Bender.yml` contains a typo (`adbg_axi_biu.sv,`) that newer
  bender versions reject.
- `tbtools` (Questa DPI VIPs) is excluded.
- `hw/padframe/padframe_adapter.sv` is compiled from a copy in `build/` with
  a `$error` format/argument mismatch fixed, which Verilator rejects.
- pulp-runtime's linker script is regenerated in `build/ld/` with a
  configurable stack size (the original fixes it at 2 KiB).
- `env/include/libc_compat.h` is force-included in every test. It declares
  `memcmp`, `fprintf` and `snprintf`, which the runtime implements but its
  headers omit. Tests are also compiled with `-fno-builtin-fprintf`, because
  GCC otherwise turns some `fprintf` calls into `fwrite`, which the runtime
  lacks.

The full history of what was changed and why is in [CHANGES.md](CHANGES.md).

## Limitations

- **No JTAG/debug boot.** The program is loaded by backdoor, so the debug
  module and JTAG TAP are held in reset and not exercised.
- **Fixed clocks.** Changing the FLL frequency from software has no effect.
  The runtime's frequency queries return the requested value, not the real
  clock.
- **No external devices.** There are no flash, HyperRAM, camera or I2S models,
  and the UART RX pad is only pulled up. Peripheral tests that need an
  external device need a model added to the TB.
- **printf goes through the simulation-only virtual stdout**, not the UART.
- **RTL edits don't trigger a model rebuild.** Run `make clean` after changing
  hardware sources.
- Simulation speed is about 350–500 µs of simulated time per wall-clock
  second, roughly 20k core cycles/s.
