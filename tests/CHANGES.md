# PULPissimo Verilator test environment: change log

Context for a future session (human or Claude) picking up this work. For
day-to-day usage, see [README.md](README.md).

## Current state at a glance

| | |
|---|---|
| **Repo** | `/home/baris/gstl/pulpissimo-pqc` (a copy of `/home/baris/gstl/pulpissimo`) |
| **Constraint** | Do **not** modify upstream/tracked code. Everything lives in `tests/`. Exceptions, all at the user's request: `/kyber/` and `/dilithium/` in the root `.gitignore` (the user prefers the root-anchored form), and a note at the top of the root `README.md` pointing to `tests/` (the rest of that README is unchanged). |
| **Simulator** | Verilator, both cores (`CORE=cv32e40p` default, `CORE=ibex`) |
| **Tests** | `hello`, `l2_preload`, `cycle_count`, `kyber_ref`, `kyber_cycles`, `dilithium_ref`, `dilithium_cycles` |
| **Hardware** | No JTAG adapter yet; board not confirmed (Nexys Video or Nexys 4 DDR) |
| **Open issue** | [The simulator does not rebuild when RTL changes](#open-issue-simulator-does-not-rebuild-when-rtl-changes) |

### Kyber cycle counts (headline result, current code)

| Parameter set | Operation | CV32E40P | Ibex |
|---|---|---:|---:|
| Kyber512 | `crypto_kem_keypair` | 926,508 | 1,276,781 |
| | `crypto_kem_enc` | 1,068,539 | 1,451,933 |
| | `crypto_kem_dec` | 1,238,966 | 1,707,637 |
| Kyber768 | `crypto_kem_keypair` | 1,525,556 | 2,102,196 |
| | `crypto_kem_enc` | 1,741,674 | 2,388,046 |
| | `crypto_kem_dec` | 1,959,668 | 2,724,962 |
| Kyber1024 | `crypto_kem_keypair` | 2,386,757 | 3,306,081 |
| | `crypto_kem_enc` | 2,637,353 | 3,649,998 |
| | `crypto_kem_dec` | 2,913,387 | 4,074,590 |

Details in [Kyber parameter sweep](#2026-10-26-kyber-parameter-sweep-kyber_k--2-3-4).

### Dilithium2 cycle counts (headline result)

| Operation | CV32E40P | Ibex |
|---|---:|---:|
| `crypto_sign_keypair` | 3,307,132 | 4,470,567 |
| `crypto_sign` | 22,185,892 | 27,902,534 |
| `crypto_sign_open` | 3,582,361 | 4,769,927 |
| Peak stack | 52,692 B | 52,692 B |

Details in [Dilithium](#2026-10-26-dilithium-ml-dsa-testsdilithium_ref-and-testsdilithium_cycles).

---

## 2026-10-26: Initial environment

### Goal

The user's simulator is Verilator. Upstream PULPissimo supports only Questa
and Xcelium; its README says Verilator support is "planned, but not
finished". The user wanted a `tests/` folder where tests can be dropped in
and run. **Hard constraint:** do not modify original/tracked code.
Everything lives in `tests/`, plus gitignored dependency checkouts.

### User's machine

| Tool | Details |
|---|---|
| Verilator | 5.053 (devel), `/usr/local/bin/verilator` |
| GCC | Stock `riscv32-unknown-elf-gcc` 16.1 in `~/riscv32/bin`. No PULP extensions (`xcorev`, `xpulpv2`, `xgap9` are all rejected). Defaults to C23, which breaks pulp-runtime (K&R `int (*)()` prototypes). The only hard-float multilib is `rv32imafc/ilp32f`. |
| Questa / Xcelium | Not installed |
| Vivado | 2026.1 at `/mnt/depo/Xilinx/2026.1` |

### Actions outside `tests/`

All gitignored; no tracked file touched.

- Ran `make checkout` in the repo root. It installed bender into
  `utils/bin/bender` (0.31.0, although `utils.mk` asks for 0.28.0) and
  checked out all IPs into `.bender/`.

### Files created

| File | Purpose |
|---|---|
| `tests/Makefile` | Top-level flow: `hw` / `sw` / `run` / `all-tests` / `clean` |
| `tests/README.md` | User documentation |
| `tests/.gitignore` | Ignores `build/` |
| `tests/CHANGES.md` | This file (formerly `changes.log`) |
| `tests/env/tb_verilator.sv` | Testbench top (`module tb_verilator`) |
| `tests/env/clock_gen_verilator.sv` | Drop-in `module clock_gen` replacement |
| `tests/env/pad_functional_verilator.sv` | `pad_functional_pu` / `_pd` replacements |
| `tests/env/elf2mem.py` | ELF → `entry` + `addr data` lines image |
| `tests/env/sw.mk` | Builds one test with `sw/pulp-runtime` |
| `tests/hello/hello.c` | `printf` + `return 0` |
| `tests/l2_preload/l2_preload.c` | 96 KiB const table spanning pri0, pri1 and the interleaved L2; verifies the backdoor mapping |

### How it works

**Hardware build** (`make hw` → `build/sim-<core>/Vtb_verilator`)

1. The file list comes from
   ```
   bender -d <root> script verilator --no-default-target \
     -t rtl -t rtl_sim -t verilator -e adv_dbg_if -e tbtools
   ```
   with `deprecated/pad_functional.sv` dropped and these appended:
   `env/pad_functional_verilator.sv`,
   `hw/vendored_ips/gpio/src/gpio_input_stage.sv`, the `adv_dbg_if` RTL
   files (listed by hand) plus incdir, `build/.../padframe_adapter.sv`
   (patched copy), `env/clock_gen_verilator.sv`, `env/tb_verilator.sv`.
2. `verilator --binary --timing --trace-fst`, top `tb_verilator`,
   `-GCORE_TYPE` / `-GUSE_FPU` from `CORE=cv32e40p|ibex`, many `-Wno-*` (see
   the Makefile).

`files.f` depends on the Makefile, so editing the Makefile rebuilds the
model.

**Software build** (`make sw` → `build/sw-<core>/<test>/`)

```
make -C tests/<test> -f env/sw.mk TEST=<test> TARGET_BUILD_DIR=...
```

`sw.mk` exports the variables normally set by
`source sw/pulp-runtime/configs/pulpissimo_cv32.sh`, compiles every
`*.c`/`*.S` in the test folder, and includes the test's optional `test.mk`.
Then `elf2mem.py` writes `<test>.mem` and objdump writes `<test>.dis`.

| Core | Compile flags | Link flags |
|---|---|---|
| CV32E40P | `-march=rv32imfc_zicsr_zifencei -mabi=ilp32f -std=gnu11` | `-march=rv32imafc_zicsr_zifencei -mabi=ilp32f` |
| Ibex | `-march=rv32imc_zicsr_zifencei -mabi=ilp32 -std=gnu11` | `-march=rv32imc_zicsr_zifencei -mabi=ilp32` |

CV32E40P links with "a" only so GCC picks the `ilp32f` libgcc multilib. The
code itself has no atomics, which the core lacks.

**Simulation** (`make run` → `Vtb_verilator +MEM=... +TIMEOUT_US=... [+WAVES=f.fst]`)

`tb_verilator.sv`:

- ~32.768 kHz ref clock. Pads are connected through wires, because Verilator
  rejects constants on inout ports.
- `bootsel = 3`; JTAG is held in reset.
- While in reset, it backdoor-writes the L2 SRAM arrays.
  `tc_sram` with `SimInit="none"` does not clear its contents on reset.

  | Region | Hierarchy (under `i_dut.i_soc_domain.i_pulp_soc.l2_ram_i`) | Start | Size |
  |---|---|---|---|
  | Private bank 0 | `bank_sram_pri0_i.sram` | `0x1C000000` | 8K words |
  | Private bank 1 | `bank_sram_pri1_i.sram` | `0x1C008000` | 8K words |
  | Interleaved | `CUTS[0..3].bank_i.sram`; bank = `addr[3:2]`, row = `off[17:4]` | `0x1C010000` | 4 × 16K words |

- `force i_dut.i_soc_domain.i_pulp_soc.s_fc_bootaddr = entry` skips the
  bootrom (the `FC_BOOTADDR` register resets to the bootrom at `0x1A000080`).
- End of test: it watches
  `...soc_peripherals_i.s_soc_ctrl_reg_reg2hw.corestatus.{eoc,exit_code}.q`
  (pulp-runtime's `exit()` writes CORESTATUS at `0x1A1040A0`).

  | Outcome | TB action | Process exit code |
  |---|---|---|
  | Exit code 0 | `$finish` | 0 |
  | Exit code ≠ 0 | `$fatal` | ≠ 0 |
  | Timeout | `$fatal` | ≠ 0 |

- `printf` output goes through the `SIM_STDOUT` virtual peripheral
  (`tb_fs_handler` in pulp_soc), printed as `[STDOUT-CL31_PE0, <time>] ...`.

`clock_gen_verilator.sv`:

- `soc_clk` and `per_clk` come from `always #10ns` (50 MHz).
- It keeps `apb_to_fll` and stubs each FLL's 4 registers (status, conf1,
  conf2, integrator) with runtime-compatible reset values.
- `ack` is `req` delayed by one cycle, and `rdata` is latched on the rising
  edge of `req`, because `apb_to_fll` zeroes `addr` once `ack` is seen.
  Lock is always 1.

### Upstream problems worked around

The originals are untouched.

| # | Problem | Workaround |
|---|---|---|
| 1 | The FLL model (`generic_FLL`) is VHDL, which Verilator can't compile. `Bender.yml` already excludes `clock_gen_generic.sv` and `padframe_adapter.sv` for the `verilator` target. | We supply both ourselves. |
| 2 | `bender script verilator` implicitly adds the `synthesis` target, which drops `tb_fs_handler` (printf) and the tech_cells deprecated cells. | `--no-default-target` |
| 3 | `adv_dbg_if`'s `Bender.yml` has the typo `rtl/adbg_axi_biu.sv,` (trailing comma); bender 0.31 raises E31. The package is still needed (`lint_jtag_wrap` uses `adbg_lintonly_top`). | Excluded from bender; its files are listed in the Makefile. |
| 4 | tech_cells_generic `deprecated/pad_functional.sv` uses `rpmos`/`bufif0`, which Verilator doesn't support. | Replaced by `env/pad_functional_verilator.sv` (always pulled; `PEN` ignored). |
| 5 | `hw/padframe/padframe_adapter.sv:140` has a `$error` with two `%0d` but one argument; Verilator raises a hard error. | The Makefile sed-patches a copy into `build/sim-<core>/padframe_adapter.sv`. |
| 6 | tbtools `dpi_models.sv` fails to elaborate (QSPI interface members); it's a Questa-only VIP. | Package excluded. |
| 7 | With Ibex, pulp_soc `fc_subsystem.sv` passes ints to enum parameters (ENUMVALUE error). | `-Wno-ENUMVALUE` |
| 8 | Verilator quirk: a comment whose text starts with "Verilator" at the top of a `.sv` file is parsed as a pragma (BADVLTPRAGMA). | File headers are worded to avoid it. |

### Verified

| Check | Result |
|---|---|
| CV32E40P: `hello`, `l2_preload` | PASS (`make all-tests` exit code 0) |
| Ibex: `hello`, `l2_preload` | PASS |
| `return 3` from `main` | FAILED, exit code ≠ 0 |
| Infinite loop | TIMEOUT, exit code ≠ 0 |
| `WAVES=1` | Produces an FST |
| Performance | Model build ~90 s on 8 threads; ~350–500 µs simulated per wall-clock second (~20k cycles/s); `hello` ~2 s end-to-end |

### Known limitations

- No JTAG/debug-module boot path (backdoor loading only).
- Fixed clocks; programming the FLL has no effect on the real frequency.
- No external device models (flash, HyperRAM, camera, I2S); the UART RX pad
  is only pulled up. Peripheral tests need models added to
  `tb_verilator.sv`.
- `printf` goes through the virtual stdout, not the UART.
- `build/lint.log` is a stale artifact from the first bring-up lint runs and
  can be ignored. `build/` is generated; `make clean` removes it.

---

## 2026-10-26: Physical hardware, cycle accuracy, area/power

Research only; nothing built yet.

### Status

- The user has **no JTAG adapter** right now.
- The board is not confirmed: Nexys Video or Nexys 4 DDR.
- Software-only for now.

| Open offer | Status |
|---|---|
| Cycle-counting helper plus an example test | **Done**: `env/include/cycles.h`, `tests/cycle_count` |
| Vivado area/power target in `tests/` | Not started |
| UART program loading for the board (option C below) | Not started |

### Board support (upstream `target/fpga/`)

| | Nexys Video | Nexys 4 DDR |
|---|---|---|
| Build | `make nexys_video` in `target/fpga` | `make nexys rev=nexys4DDR` |
| FPGA | `xc7a200tsbg484-1` | `xc7a100tcsg324-1` (the 320 KiB L2 = 4×64 + 2×32 KiB fits in BRAM) |
| SoC JTAG | Channel 0 of the **on-board** FTDI (PROG micro-USB J12); **no adapter needed** | PMOD JA pins 1–6 (TMS, TDI, TDO, TCK, GND, VCC); **external adapter required** |
| OpenOCD config | `pulpissimo-nexys_video/openocd-nexys_video.cfg` | `pulpissimo-nexys/openocd-nexys-hs2.cfg` |
| Clocks | SoC 10 MHz, peripheral 5 MHz | SoC 10 MHz, peripheral 5 MHz |
| UART | On-board USB-UART | On-board USB-UART |

Both boards:

- There is a CPU reset button.
- `bootsel` is tied to 0 in `run.tcl`, so the bootrom starts the zforth shell
  on the UART (zforth takes priority over UART-srec boot in
  `sw/bootcode/boot_code.c`).

Risks:

- The upstream FPGA scripts target an older Vivado than the installed
  2026.1; the clk_wiz IPs may need regenerating.
- OpenOCD is **not** installed (it needs the riscv target and ftdi support).
  `riscv32-unknown-elf-gdb` is installed.

### Ways to get a program onto the board

| Option | How | Verdict |
|---|---|---|
| **A. JTAG + OpenOCD + GDB** (upstream flow, `elf_run.gdb`) | GDB loads the ELF into L2, sets the PC and continues. The exit status is read from CORESTATUS `0x1A1040A0` over JTAG; printf comes from the UART. | **Best for tests**: seconds per test, no rebuild, real debugger. Planned: `make run TEST=x PLATFORM=fpga BOARD=nexys_video` with the same PASS/FAIL exit codes as the simulator. |
| B. Program in the bitstream | L2 BRAM init (Vivado `updatemem`, needs an MMI) plus a boot address change | One bitstream per program; standalone demos only |
| C. UART loading, no JTAG | Rebuild the FPGA bootrom without `ENABLE_ZFORTH_BOOT` so UART-srec boot is used. Build that bootrom in `tests/`, **not** via `make bootrom` (which overwrites `hw/fpga_autogen_rom.sv`). | One bitstream rebuild, then any test over the USB-UART. No debugger; the exit code must be reported over UART. The no-adapter option for the Nexys 4 DDR. |
| D. QSPI flash boot (`bootsel=2`) | Program stored in flash | Standalone deployment only |

Sharing tests between simulation and hardware would need `PLATFORM=sim|fpga`
in `sw.mk`. For the FPGA, pulp-runtime is built with `platform=fpga`, which
turns on `CONFIG_IO_UART=1`, so printf goes to the real UART.

### Cycle accuracy: simulation vs. hardware

The core, interconnect, L2 and peripherals are the same RTL, so **core-cycle
counts for code that only touches the core and L2 are identical** in
simulation and on the FPGA. The differences:

| Difference | Simulation | FPGA | Effect |
|---|---|---|---|
| Clocks | SoC and peripheral at 50 MHz | SoC 10 MHz, peripheral 5 MHz | Compare cycles, not time. Peripheral/uDMA latency in core cycles differs because the core:peripheral ratio differs. |
| `printf` | Virtual stdout, a few cycles | UART at 115200 baud, ~870 core cycles per character at 10 MHz | **Never time code that prints.** |
| Clock generation | Stub reports the FLL locked instantly | Xilinx clocking | Only startup before `main()` is affected |
| Wall-time waits (timer, ms) | | | Different cycle count |

Method: read `mcycle` around the region of interest and print the result
afterwards (`cycles.h`).

### Area and power

Verilator gives function only, no area or power.

| Option | What you get | Notes |
|---|---|---|
| **A. Vivado** (recommended; installed) | `report_utilization` after synthesis/implementation: LUT/FF/BRAM/DSP per hierarchy. `report_power`: a vectorless guess, or per-test power from simulation activity. | For per-test power, dump waves from the Verilator run over the region of interest, convert to SAIF (or use VCD if Vivado accepts it), map TB `tb_verilator.i_dut` onto FPGA top `xilinx_pulpissimo.i_pulpissimo`, then run `report_power`. These are FPGA numbers, good for comparing design changes, not for predicting an ASIC. |
| B. ASIC-style | Yosys (needs sv2v or yosys-slang) + OpenROAD/OpenSTA with a public PDK (e.g. SKY130): area in µm², activity-annotated power | Much more effort: the SRAMs need memory macros or they become huge flip-flop arrays, and run times are long. |

### JTAG adapter: Digilent JTAG-HS2

- **Compatible.** The Nexys 4 target was designed around it: the PMOD JA
  pinout matches the HS2's 6-pin header.
- Upstream ships `target/fpga/pulpissimo-nexys/openocd-nexys-hs2.cfg`
  (FTDI `0403:6014`). It uses old OpenOCD syntax (`interface ftdi`,
  `adapter_khz`); current OpenOCD needs `adapter driver ftdi`,
  `adapter speed`, etc. Adapt it in a copy under `tests/`.
- Not needed for the Nexys Video, which has on-board JTAG.

---

## 2026-10-26: `cycle_count` test and `cycles.h`

### Context: repo copy

Work moved to a copy of the repo at `/home/baris/gstl/pulpissimo-pqc`. The
copied `tests/build/` still pointed at `/home/baris/gstl/pulpissimo/`:
bender emits absolute paths, and the copied timestamps did not trigger a
rebuild. So the simulator was built from the **other** repo's RTL. Fixed with
`make clean` and a rebuild.

> **If the repo is copied or moved again, run `make clean` first.**

### Files

| File | Purpose |
|---|---|
| `tests/env/include/cycles.h` | `cycles_enable` / `cycles_read` (64-bit `mcycleh`/`mcycle` with a wrap-safe re-read) / `cycles_overhead` / `cycles_print` |
| `tests/env/sw.mk` | Adds `-I$(ENV_DIR)include` to every test |
| `tests/cycle_count/cycle_count.c` | Example: measure one `noinline` call (FNV-1a over 256 words), print afterwards |
| `tests/README.md` | New "Measuring cycles" section |

### Facts learned

- CV32E40P resets the implemented `mcountinhibit` bits to 1, so its counters
  are **off** (`cv32e40p_cs_registers.sv`, "default disable").
  `cycles_enable()` clears bit 0 (CY). Ibex counts by default; clearing the
  bit is harmless there.
- The minimal libc `printf` ignores length modifiers and reads every integer
  as 32-bit, so `%llu` doesn't work. `cycles_print()` formats `uint64_t`
  itself.
- CSR numbers are used directly (`0x320`, `0xB00`, `0xB80`), independent of
  the assembler's CSR name support.

### Results

Deterministic across runs:

| Core | Cycles | Overhead (subtracted) | Notes |
|---|---:|---:|---|
| CV32E40P | 1806 | 13 | ~7 cycles/iteration; code runs from L2, no I-cache |
| Ibex | 2573 | 4 | |

Both: result `0xfd44f0c5`; `all-tests` 3/3 PASS.

### What "measurement overhead" means

The counter is sampled in the middle of `cycles_read()` (the `mcycle` read
between the two `mcycleh` reads). `end - start` therefore also includes the
tail of the first read and the head of the second. `cycles_overhead()`
measures exactly that with two back-to-back reads, and it is subtracted. The
counts differ per core because of pipeline differences. The overhead is
negligible for Kyber-sized functions but matters for very short ones.

---

## Open issue: simulator does not rebuild when RTL changes

**Not fixed yet.** The user deferred the fix on 2026-10-26.

- In `tests/Makefile`, `$(SIM_BIN)` depends only on `files.f`, the patched
  `padframe_adapter.sv`, `env/tb_verilator.sv` and
  `env/clock_gen_verilator.sv`. `files.f` depends only on `Bender.lock` and
  the Makefile. **None** of the hardware sources (`hw/*.sv`,
  `.bender/git/checkouts/**`, `Bender.yml`) are prerequisites.
- **Effect:** after editing RTL (e.g. adding a PQC accelerator), `make run`
  silently keeps using the old simulator.
- **Workaround:** `make clean` (or delete `build/sim-*`) after any RTL change.

Planned fix:

1. Make `$(SIM_BIN)` depend on every source file listed in `files.f`, e.g.
   by generating a `.d` file from the non-`+` lines of `files.f`, or by
   using Verilator's own dependency file `obj/Vtb_verilator__ver.d`.
2. Make `files.f` also depend on `Bender.yml` (root and `hw/padframe`) so
   added or removed files are picked up.

Related: `build/` holds absolute paths (bender output), so after copying or
moving the repo, run `make clean`.

---

## 2026-10-26: Kyber (ML-KEM) reference test: `tests/kyber_ref`

### Source

- https://github.com/pq-crystals/kyber, commit `3edd5af5`, folder `ref/`.
- Cloned to `<repo>/kyber/`, which is in the **root** `.gitignore` as
  `/kyber/`. This change to a tracked upstream file was made at the user's
  request. The other one is the note at the top of the root `README.md`.
- The needed `ref/` files are copied unchanged into `tests/kyber_ref/`.
  Modifications are documented in
  [kyber_ref/README.md](kyber_ref/README.md):

| File | Change |
|---|---|
| `test_kyber.c` (from `ref/test/`) | Include paths; `NTESTS` wrapped in `#ifndef` |
| `randombytes.c` | Replaced by a deterministic xorshift32 PRNG with a fixed seed. **Not secure**, but reproducible. |

### Infrastructure changes (apply to all tests)

| Change | Details |
|---|---|
| **Stack size** | pulp-runtime's `link.ld` hard-codes a 2 KiB stack (`. = . + 0x800`). `tests/Makefile` generates `build/ld/chips/pulpissimo/link.ld` with `DEFINED(__stack_size) ? __stack_size : 0x800`. `sw.mk` puts `-L<that dir>` first in `PULP_ARCH_LDFLAGS` (shadowing the runtime's script) and passes `-Wl,--defsym=__stack_size=$(STACK_SIZE)`. The default `0x800` equals upstream; a test sets `STACK_SIZE` in its `test.mk`. |
| **Stack overflow is silent** | It corrupts memory below `stack_start`, so size stacks generously. |
| **Per-test make variables** | `tests/Makefile` also `-include`s `<test>/test.mk`, so a test can set `TIMEOUT_US` etc. Command-line values still win. |
| **`libc_compat.h`** | `env/include/libc_compat.h` is force-included in every test. The minimal libc's `string.h` lacks a `memcmp` prototype although `io.c` implements it, and GCC 16 makes implicit declarations an error. |
| **RWX linker warning** | With a large stack the linker merges code and data into one LOAD segment and warns "LOAD segment with RWX permissions". Harmless on both cores: Ibex has `PMPEnable=0` (pulp_soc `fc_subsystem.sv`), CV32E40P has no PMP configured, and pulp-runtime never programs `pmpcfg`/`pmpaddr`. |

### Kyber settings (`tests/kyber_ref/test.mk`)

| Variable | Value | Meaning |
|---|---|---|
| `KYBER_K` | `3` | Kyber768 (2 = 512, 4 = 1024) |
| `NTESTS` | `1` | Upstream uses 1000, far too slow in RTL simulation |
| `STACK_SIZE` | `0x8000` | 32 KiB |
| `TIMEOUT_US` | `2000000` | |

> ~~Flag-only changes (`KYBER_K`, `NTESTS`) do not trigger recompilation. Run
> `make clean-sw` first.~~ Superseded: each configuration now has its own
> build directory (`SW_VARIANT`, see the
> [Kyber sweep](#2026-10-26-kyber-parameter-sweep-kyber_k--2-3-4)), so no
> clean is needed.

### Result (CV32E40P, `NTESTS=1`)

- **PASSED.** One iteration runs keypair + enc + dec three times.
- Printed sk 2400, pk 1184, ct 1088 bytes (correct for Kyber768).
- Simulated time ~308.5 ms at 50 MHz (~15.4M cycles including startup and
  printf). **Wall time 13 min** (~395 µs/s).
- `make all-tests` now includes `kyber_ref` and takes 13+ minutes.
- Not yet run on Ibex.

---

## 2026-10-26: Kyber cycle counts: `tests/kyber_cycles`

- A separate test. It compiles the Kyber sources from `../kyber_ref` through
  `test.mk` (`PULP_APP_SRCS +=` all `../kyber_ref/*.c` except
  `test_kyber.c`, plus `-I../kyber_ref`), so there is **one** copy of the
  Kyber code. The objects land in `build/sw-<core>/kyber_cycles/kyber_ref/`.
- `kyber_cycles.c` measures `crypto_kem_keypair`, `crypto_kem_enc` and
  `crypto_kem_dec` separately with `cycles.h`, prints afterwards, and fails
  if the shared keys differ.
- pk/sk/ct/keys are `static`, so they don't count against the stack.

### Results

Kyber768 (`KYBER_K=3`), `-O2`, fixed-seed RNG; deterministic.

| Operation | CV32E40P | Ibex |
|---|---:|---:|
| `crypto_kem_keypair` | 1,525,439 | 2,102,051 |
| `crypto_kem_enc` | 1,741,553 | 2,387,903 |
| `crypto_kem_dec` | 1,959,591 | 2,724,809 |
| Overhead (subtracted) | 13 | 4 |
| Wall time | 4.5 min | 7.6 min |

- Consistency check: the CV32E40P sum (5.23M) × 3 roughly matches the
  ~15.4M-cycle `kyber_ref` iteration.
- Both cores run plain RV32IM(F)C code from stock GCC 16; no PULP/XCV
  extensions are used.

---

## 2026-10-26: Kyber parameter sweep (`KYBER_K` = 2, 3, 4)

### Infrastructure: per-configuration build directories (`SW_VARIANT`)

- `tests/Makefile`: `SW_DIR = build/sw-<core>/<test>$(if $(SW_VARIANT),-$(SW_VARIANT))`.
  A test sets `SW_VARIANT` in its `test.mk` (which the top Makefile already
  includes).

  | Test | `SW_VARIANT` | Example directory |
  |---|---|---|
  | `kyber_ref` | `k$(KYBER_K)-n$(NTESTS)` | `kyber_ref-k3-n1` |
  | `kyber_cycles` | `k$(KYBER_K)` | `kyber_cycles-k2` |
  | `dilithium_ref` | `mode$(DILITHIUM_MODE)-n$(NTESTS)` | `dilithium_ref-mode2-n1` |
  | `dilithium_cycles` | `mode$(DILITHIUM_MODE)` | `dilithium_cycles-mode2` |

- **Effect:** switching `KYBER_K` / `NTESTS` / `DILITHIUM_MODE` no longer
  needs `make clean-sw` (that caveat is removed from all READMEs), and several
  configurations can build and run in parallel.
- Old directories without a suffix (`build/sw-*/kyber_cycles`, etc.) are
  stale leftovers; `make clean-sw` removes them.

### `kyber_cycles` now reports stack usage

`stack_paint()` before the measurements; it prints `peak stack usage` and
fails on `stack_overflowed()`, the same as `dilithium_cycles`.

### Results

All six runs PASSED (shared keys match). They ran in parallel; wall times
were 4–13 min each.

| Parameter set | Operation | CV32E40P | Ibex | Ibex / CV32E40P | CV32E40P @ 10 MHz | Ibex @ 10 MHz |
|---|---|---:|---:|---:|---:|---:|
| Kyber512 | keypair | 926,508 | 1,276,781 | 1.38 | 92.7 ms | 127.7 ms |
| | enc | 1,068,539 | 1,451,933 | 1.36 | 106.9 ms | 145.2 ms |
| | dec | 1,238,966 | 1,707,637 | 1.38 | 123.9 ms | 170.8 ms |
| Kyber768 | keypair | 1,525,556 | 2,102,196 | 1.38 | 152.6 ms | 210.2 ms |
| | enc | 1,741,674 | 2,388,046 | 1.37 | 174.2 ms | 238.8 ms |
| | dec | 1,959,668 | 2,724,962 | 1.39 | 196.0 ms | 272.5 ms |
| Kyber1024 | keypair | 2,386,757 | 3,306,081 | 1.39 | 238.7 ms | 330.6 ms |
| | enc | 2,637,353 | 3,649,998 | 1.38 | 263.7 ms | 365.0 ms |
| | dec | 2,913,387 | 4,074,590 | 1.40 | 291.3 ms | 407.5 ms |

| Parameter set | Peak stack (both cores) | of `STACK_SIZE` |
|---|---:|---:|
| Kyber512 | 9,908 B | 32,768 B |
| Kyber768 | 14,804 B | 32,768 B |
| Kyber1024 | 20,916 B | 32,768 B |

### Note: layout-dependent drift in cycle counts

The Kyber768 counts differ slightly from the [first `kyber_cycles`
run](#2026-10-26-kyber-cycle-counts-testskyber_cycles), although the Kyber
code is unchanged:

| Kyber768 | First run | Now | Δ |
|---|---:|---:|---:|
| CV32E40P keypair / enc / dec | 1,525,439 / 1,741,553 / 1,959,591 | 1,525,556 / 1,741,674 / 1,959,668 | +117 / +121 / +77 |
| Ibex keypair / enc / dec | 2,102,051 / 2,387,903 / 2,724,809 | 2,102,196 / 2,388,046 / 2,724,962 | +145 / +143 / +153 |

What changed in between: `main()` grew (the stack report), and
`-fno-builtin-fprintf` / `libc_compat.h` were added. This moves the Kyber
functions and the static buffers to different addresses, and alignment of
instruction fetches and data accesses costs a few cycles differently. The
effect is ~0.01%. **Compare numbers produced by the same build of the
test code**; the "current code" numbers above supersede the first run's.

---

## 2026-10-26: Dilithium (ML-DSA): `tests/dilithium_ref` and `tests/dilithium_cycles`

Set up exactly like Kyber: one copy of the code in `dilithium_ref/`, and a
separate cycles test that compiles it from there.

### Source

- https://github.com/pq-crystals/dilithium, commit `d35ba3fe`, folder
  `ref/`.
- Cloned to `<repo>/dilithium/`, added to the root `.gitignore` as
  `/dilithium/`. (The user tried `kyber/` for the VS Code grey-out but kept
  `/kyber/`, so both use the root-anchored form. `./kyber` does **not**
  work in `.gitignore`; this was tested.)
- The needed `ref/` files are copied unchanged. Modifications are documented
  in [dilithium_ref/README.md](dilithium_ref/README.md):

| File | Change |
|---|---|
| `test_dilithium.c` (from `ref/test/`) | Include paths; `NTESTS` (upstream 10000) wrapped in `#ifndef` |
| `randombytes.c` | Same fixed-seed xorshift32 PRNG as `kyber_ref` (the header comment of both now says "upstream ref/randombytes.c") |

### Infrastructure changes (apply to all tests)

| Change | Details |
|---|---|
| **`libc_compat.h`** | Now also includes `<stdio.h>` and declares `fprintf` and `snprintf`. The minimal libc implements them (`fprintf.c`, `sprintf.c`) but `stdio.h` doesn't declare them. `stderr` is `(FILE*)3` and prints to the same output as stdout. |
| **`-fno-builtin-fprintf`** | Added in `sw.mk`. GCC rewrites `fprintf(stderr, "constant\n")` into `fwrite()`, which the minimal libc lacks (link error). |
| **`env/include/stack.h`** | New. Stack painting: `stack_paint()`, `stack_max_used()`, `stack_size()`, `stack_overflowed()`. Uses the linker symbols `stack_start` / `stack`. The result includes `main()`'s frame. |

### Settings

| Variable | Value | Notes |
|---|---|---|
| `DILITHIUM_MODE` | `2` | Upstream default (2, 3 or 5) |
| `NTESTS` | `1` | `dilithium_ref` only |
| `STACK_SIZE` | `0x20000` (128 KiB) | Measured peak for Dilithium2 in `dilithium_cycles`: 52,692 B. `dilithium_ref` adds ~11 KiB of arrays on its own stack (m, m2, sm, pk, sk). **Modes 3/5 are not measured**; `dilithium_cycles` fails with a message on overflow, `dilithium_ref` has no such check. |
| `TIMEOUT_US` | `4000000` | Dilithium2 needs ~0.6 s simulated; larger modes need more |

`dilithium_cycles` measures the API calls used by the upstream test:
`crypto_sign_keypair`, `crypto_sign` (= `crypto_sign_signature` plus a copy
of the message) and `crypto_sign_open` (= `crypto_sign_verify` plus a copy).
All buffers are `static`; message and context are the same as in
`test_dilithium.c`. It fails on verification failure or stack overflow.

### Results

Dilithium2, `-O2`, fixed-seed RNG; deterministic.

| Operation | CV32E40P | Ibex | CV32E40P @ 10 MHz | Ibex @ 10 MHz |
|---|---:|---:|---:|---:|
| `crypto_sign_keypair` | 3,307,132 | 4,470,567 | 330.7 ms | 447.1 ms |
| `crypto_sign` | 22,185,892 | 27,902,534 | 2,218.6 ms | 2,790.3 ms |
| `crypto_sign_open` | 3,582,361 | 4,769,927 | 358.2 ms | 477.0 ms |
| Overhead (subtracted) | 13 | 4 | | |
| Peak stack | 52,692 B | 52,692 B | | |
| Wall time | 25 min | 39 min | | |

- `dilithium_ref` (CV32E40P, `NTESTS=1`): **PASSED**, printed pk 1312,
  sk 2560, signature 2420 bytes (correct for Dilithium2). Wall time 28.5 min.
  Not yet run on Ibex.
- **Signing varies with the input** (rejection sampling). The count is one
  sample for the fixed seed; benchmarks usually report a median over many
  runs. Not done here: each Dilithium2 signature takes ~18 min of wall time.
- `make all-tests` now takes well over an hour.

---

## Reference: clock frequencies

### Clock domains

| Domain | Drives | Note |
|---|---|---|
| FC / SoC clock | Core, L2, interconnect | **Cycle counts are in this clock** |
| Peripheral clock | uDMA peripherals (UART, SPI, I2C, …) | |
| Slow / ref clock | Timers, RTC-style events | 32.768 kHz everywhere |

### Frequencies per target

The frequencies do **not** depend on the core.

| Target | SoC (FC) | Peripheral |
|---|---:|---:|
| Verilator simulation (`env/clock_gen_verilator.sv`) | 50 MHz | 50 MHz |
| `nexys` (Nexys 4 / 4 DDR / A7) | 10 MHz | 5 MHz |
| `nexys_video` | 10 MHz | 5 MHz |
| `genesys2` | 20 MHz | 10 MHz |
| `vcu108` | 20 MHz | 10 MHz |
| `zcu102` | 16 MHz | 10 MHz |
| `zcu104` | 16 MHz | 10 MHz |
| `zcu106` | 13.3 MHz | 10 MHz |
| `zedboard` | 16 MHz | 10 MHz |

- FPGA values come from `target/fpga/pulpissimo-<board>/fpga-settings.mk`
  (`*_CLK_PERIOD_NS`). These periods drive **both** the clk_wiz IP generation
  (`ips/xilinx_clk_mngr/tcl/run.tcl`: `FREQ_MHZ = 1000 / PERIOD_NS`) and the
  timing constraints in `tcl/run.tcl`.
- The defaults when unset (SoC 100 MHz, peripheral 50 MHz) are never used;
  every board sets the variables.
- The upstream frequencies are conservative. Higher ones may close timing
  but have not been tried.

### Core choice on FPGA

`target/fpga/pulpissimo-*/rtl/xilinx_pulpissimo.v` hard-codes
`localparam CORE_TYPE = 0; USE_FPU = 1;` (CV32E40P with FPU). An Ibex
bitstream needs `CORE_TYPE = 1`, set in a copy of that file so upstream
stays untouched. **Not done yet.**

### PQC time at the Nexys SoC clock (10 MHz)

Time = cycles / 10 MHz. The cycle counts are in the
[Kyber sweep](#2026-10-26-kyber-parameter-sweep-kyber_k--2-3-4) and
[Dilithium](#2026-10-26-dilithium-ml-dsa-testsdilithium_ref-and-testsdilithium_cycles)
sections.

| Algorithm | Operation | CV32E40P | Ibex |
|---|---|---:|---:|
| Kyber512 | keypair / enc / dec | 92.7 / 106.9 / 123.9 ms | 127.7 / 145.2 / 170.8 ms |
| Kyber768 | keypair / enc / dec | 152.6 / 174.2 / 196.0 ms | 210.2 / 238.8 / 272.5 ms |
| Kyber1024 | keypair / enc / dec | 238.7 / 263.7 / 291.3 ms | 330.6 / 365.0 / 407.5 ms |
| Dilithium2 | keypair / sign / open | 330.7 / 2,218.6 / 358.2 ms | 447.1 / 2,790.3 / 477.0 ms |

At the simulator's 50 MHz the times are 5× shorter. The cycle counts are
identical; only peripheral-bound code depends on the SoC:peripheral clock
ratio.
