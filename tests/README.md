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
rebuilt only when the environment files change.

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
```

pulp-runtime headers (`pulp.h`, HAL, drivers) are on the include path. See
`sw/pulp-runtime` and `sw/regression_tests` for examples of peripheral access.

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
- Simulation speed is about 350–500 µs of simulated time per wall-clock
  second, roughly 20k core cycles/s.
