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
| `kyber_cycles` | Cycle counts of Kyber keypair / encapsulation / decapsulation | ~4.5 min |
| `dilithium_ref` | Upstream Dilithium functional test (`test_dilithium.c`), see [Dilithium](#dilithium-ml-dsa) | ~28 min |
| `dilithium_cycles` | Cycle counts of Dilithium keypair / sign / verify, plus peak stack usage | ~25 min |

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

After changing only flags (in `test.mk` or on the command line), run
`make clean-sw`: objects are rebuilt when sources change, not when flags do.

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
| `kyber_cycles` | Measures `crypto_kem_keypair`, `crypto_kem_enc` and `crypto_kem_dec` separately and prints the cycle counts |

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
[STDOUT-CL31_PE0, 104855.890 us] Kyber768
[STDOUT-CL31_PE0, 104900.910 us] crypto_kem_keypair: 1525439 cycles
[STDOUT-CL31_PE0, 104946.050 us] crypto_kem_enc    : 1741553 cycles
[STDOUT-CL31_PE0, 104991.170 us] crypto_kem_dec    : 1959591 cycles
[STDOUT-CL31_PE0, 105040.510 us] measurement overhead (subtracted): 13 cycles
[STDOUT-CL31_PE0, 105052.190 us] shared keys match
[TB] 105053.410 us: PASSED (exit code 0)
```

The test fails if the two shared keys differ, so a printed count always
belongs to a correct run.

### Options

| Variable | Default | Tests | Meaning |
|----------|---------|-------|---------|
| `KYBER_K` | `3` | both | Parameter set: `2` = Kyber512, `3` = Kyber768, `4` = Kyber1024 |
| `NTESTS` | `1` | `kyber_ref` | Iterations of the three checks. Upstream uses 1000; each iteration takes ~13 min here. |
| `CORE` | `cv32e40p` | both | `cv32e40p` or `ibex` |

Kyber needs a 32 KiB stack (`STACK_SIZE = 0x8000` in both `test.mk` files),
and its timeout is 2 s of simulated time. Larger parameter sets take
proportionally longer; if a run hits the timeout, add `TIMEOUT_US=5000000`.

**Run `make clean-sw` before changing `KYBER_K` or `NTESTS`**, otherwise the
objects compiled for the previous setting are reused:

```sh
make clean-sw && make run TEST=kyber_cycles KYBER_K=2   # Kyber512
```

### Results (Kyber768, `-O2`)

| Operation | CV32E40P (cycles) | Ibex (cycles) | CV32E40P @ 10 MHz | Ibex @ 10 MHz |
|-----------|------------------:|--------------:|------------------:|--------------:|
| `crypto_kem_keypair` | 1,525,439 | 2,102,051 | 152.5 ms | 210.2 ms |
| `crypto_kem_enc` | 1,741,553 | 2,387,903 | 174.2 ms | 238.8 ms |
| `crypto_kem_dec` | 1,959,591 | 2,724,809 | 196.0 ms | 272.5 ms |

10 MHz is the SoC clock of the Nexys FPGA targets. Both cores run plain
RV32IM(F)C code: stock GCC can't generate CV32E40P's PULP instructions.
Keep this in mind when comparing with published figures.

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
| `NTESTS` | `1` | `dilithium_ref` | Iterations. Upstream uses 10000; each iteration takes ~28 min here. |
| `CORE` | `cv32e40p` | both | `cv32e40p` or `ibex` |

Both tests use a 128 KiB stack (`STACK_SIZE = 0x20000`) and a 4 s
simulated-time limit. **The stack was only measured for Dilithium2** (52.7
KiB). Modes 3 and 5 need more: run `dilithium_cycles` for the new mode
first, since it fails with a clear message if the stack overflows.

**Run `make clean-sw` before changing `DILITHIUM_MODE` or `NTESTS`:**

```sh
make clean-sw && make run TEST=dilithium_cycles DILITHIUM_MODE=3 TIMEOUT_US=8000000
```

### Results (Dilithium2, `-O2`)

| Operation | CV32E40P (cycles) | Ibex (cycles) | CV32E40P @ 10 MHz | Ibex @ 10 MHz |
|-----------|------------------:|--------------:|------------------:|--------------:|
| `crypto_sign_keypair` | 3,307,132 | 4,470,567 | 330.7 ms | 447.1 ms |
| `crypto_sign` | 22,185,892 | 27,902,534 | 2,218.6 ms | 2,790.3 ms |
| `crypto_sign_open` | 3,582,361 | 4,769,927 | 358.2 ms | 477.0 ms |
| Peak stack | 52,692 B | 52,692 B | | |

**Signing time varies with the input.** Dilithium signing repeats an inner
loop until a candidate signature passes its checks (rejection sampling), and
the number of repetitions depends on the key, message and randomness. The
count above is one sample for the fixed seed. A different seed or message
gives a different signing count, often by a large factor. Key generation and
verification vary only slightly. Published benchmarks usually report the median over many runs.

## Outputs

`build/sw-<core>/<test>/` holds the ELF, the disassembly (`<test>.dis`), the
memory image, `sim.log` and the optional `waves.fst`.
`build/sim-<core>/` holds the Verilator model.

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
