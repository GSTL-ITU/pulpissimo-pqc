# FPGA area: PULPissimo on the Nexys 4 DDR

Synthesizes PULPissimo for the Nexys 4 DDR (XC7A100T-1CSG324, the same FPGA
as the Nexys A7-100T) with Vivado. Reports the resources of the whole design,
of the core alone, of the FPU, and of each SoC block. Same idea and table
format as `ibex-pqc/fpga`.

```sh
cd tests/fpga
make area                    # CV32E40P with FPU (the upstream FPGA configuration), ~9 min
make area CORE=ibex          # Ibex RV32IMC
make compare                 # both + side-by-side table -> ../build/fpga/compare.md
make area IMPL=1             # also place & route: post-route numbers and timing
```

Requirements: Vivado on `PATH` (or `VIVADO=<path>`; tested with 2026.1, the
free edition supports the XC7A100T) and the Bender checkout that the tests
use (`make checkout` in the repository root). About 4 GB of memory per run.

## Output

`../build/fpga/<core>/area.md` is the summary. `../build/fpga/<core>/reports/`
holds Vivado's own reports: `util_opt.rpt` (whole design),
`util_hier_opt.rpt` (every hierarchy level, deeper than the summary), and
with `IMPL=1` also `util_route.rpt`, `util_hier_route.rpt` and
`timing_route.rpt`. The build directory is `cv32e40p`, `cv32e40p-nofpu`,
`ibex` or `ibex-regff`.

## Options

| Variable | Default | Meaning |
|---|---|---|
| `CORE` | `cv32e40p` | `cv32e40p` or `ibex` (sets the top-level parameter `CORE_TYPE`) |
| `USE_FPU` | `1` | CV32E40P only: `0` leaves out the FPU (fpnew) |
| `REGFILE` | `fpga` | Ibex only: `fpga` (LUT RAM, what PULPissimo selects for FPGA targets) or `ff` (flip-flops) |
| `IMPL` | `0` | `1`: place and route too |
| `JOBS` | all cores | Vivado jobs |

Synthesis is followed by `opt_design`, which removes unused logic as
implementation would.

## Results (Vivado 2026.1, post-`opt_design`)

| | CV32E40P LUTs | FFs | BRAM | DSPs | Ibex LUTs | FFs | BRAM | DSPs |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Whole design** | 42,830 | 22,339 | 82 | 12 | 34,883 | 20,684 | 82 | 4 |
| **Core** | 7,418 | 2,660 | 0 | 7 | 3,280 | 1,387 | 0 | 1 |
| **FPU** (fpnew) | 3,723 | 382 | 0 | 2 | – | – | – | – |
| **SoC without core and FPU** | 31,689 | 19,297 | 82 | 3 | 31,603 | 19,297 | 82 | 3 |
| &nbsp;&nbsp;uDMA peripherals | 9,944 | 12,153 | 0 | 3 | 9,950 | 12,153 | 0 | 3 |
| &nbsp;&nbsp;interconnect | 5,301 | 1,044 | 0 | 0 | 5,221 | 1,044 | 0 | 0 |
| &nbsp;&nbsp;debug module and JTAG | 4,747 | 1,443 | 0 | 0 | 4,747 | 1,443 | 0 | 0 |
| &nbsp;&nbsp;event generator | 3,494 | 1,342 | 0 | 0 | 3,494 | 1,342 | 0 | 0 |
| &nbsp;&nbsp;pad frame (pad multiplexer) | 3,050 | 288 | 0 | 0 | 3,050 | 288 | 0 | 0 |
| &nbsp;&nbsp;GPIO | 1,741 | 482 | 0 | 0 | 1,741 | 482 | 0 | 0 |
| &nbsp;&nbsp;timers | 1,564 | 1,808 | 0 | 0 | 1,564 | 1,808 | 0 | 0 |
| &nbsp;&nbsp;other peripherals (APB bridge, `soc_ctrl`, ...) | 1,163 | 422 | 0 | 0 | 1,162 | 422 | 0 | 0 |
| &nbsp;&nbsp;rest of `fc_subsystem` (interrupt controller, ...) | 349 | 144 | 0 | 0 | 338 | 144 | 0 | 0 |
| &nbsp;&nbsp;L2 memory (320 KiB) | 64 | 0 | 80 | 0 | 64 | 0 | 80 | 0 |
| &nbsp;&nbsp;boot ROM, CDCs, APB decoder, glue | 272 | 171 | 2 | 0 | 272 | 171 | 2 | 0 |

Device usage (XC7A100T): CV32E40P 67.6% of the LUTs, Ibex 55.0%; both 61% of
the block RAM (L2) and ~17% of the FFs. BRAM counts 36 Kb blocks.

- **The SoC is identical** for both cores (to within 0.3%), as it should be;
  only the core and the FPU differ. CV32E40P without FPU: `make area USE_FPU=0`.
- **CV32E40P core: 7,418 LUTs**, of which the 31 × 32-bit flip-flop
  register file is 1,425 LUTs / 992 FFs. It includes the PULP extensions
  (`USE_XPULP=1`: hardware loops, post-increment loads, SIMD), which stock
  GCC doesn't use. 7 of its DSPs are the multiplier.
- **Ibex core: 3,280 LUTs**, with the LUT-RAM register file (113 LUTs, 48
  LUTRAM). Configuration from `fc_subsystem.sv`: RV32IMC with `RV32MFast`,
  10 performance counters, debug triggers, no PMP. That is the same
  configuration as the ibex-pqc demo system, whose core (a newer Ibex)
  has 3,311 LUTs and 1,369 FFs there.
- **The SoC dominates**: 74% of the LUTs with CV32E40P, 91% with Ibex. The
  biggest blocks are the uDMA peripherals (camera, filter, SDIO, HyperBus,
  I2C, QSPI, UART; the HyperBus controller alone is 2,828 LUTs / 4,817 FFs),
  the interconnect, the debug module and the event generator.

Per-block details, including the uDMA peripherals one by one, are in
`../build/fpga/<core>/area.md` and `../build/fpga/compare.md`.

## How it works

| File | Purpose |
|---|---|
| `Makefile` | Bender file list, top-level copy, Vivado, summary |
| `scripts/area.tcl` | Vivado project, clock IPs, synthesis, `opt_design`, reports (and place & route) |
| `scripts/area_summary.py` | Turns `util_hier_*.rpt` into the core/FPU/SoC tables; several reports give a comparison |

It follows the upstream Nexys flow (`target/fpga/pulpissimo-nexys/tcl/run.tcl`),
which can't be used as is: it always builds the full bitstream, writes its
project and IPs into `target/`, and hard-codes CV32E40P. Same as upstream:

- RTL from `bender script vivado -t fpga -t xilinx`; the Xilinx wrappers
  and tech cells from `target/fpga/pulpissimo-nexys/rtl/`
- defines `FPGA_TARGET_XILINX PULP_FPGA_EMUL AXI4_XCHECK_OFF NEXYS`
- the two clocking-wizard IPs with the Nexys settings (SoC 10 MHz,
  peripherals 5 MHz), the `nexys4DDR.xdc` constraints
- synthesis with `-flatten_hierarchy none` and `-sfcu`, then the
  tie-off of the unused bootsel, HyperBus and JTAG-TRST pads

Differences, all needed to make it work or to measure:

| Change | Why |
|---|---|
| Project, IPs and reports in `tests/build/fpga/` | Nothing in the repository is written |
| Top level is a copy of `xilinx_pulpissimo.v` with `CORE_TYPE` / `USE_FPU` as parameters instead of localparams | So the core can be chosen (upstream: always CV32E40P with FPU) |
| adv_dbg_if excluded from Bender, its files added by hand | Same manifest typo as for the Verilator flow (see `tests/Makefile`); Bender fails otherwise, so the upstream flow is broken too |
| Bender's target defines (`TARGET_FPGA`, `TARGET_XILINX`, `TARGET_SYNTHESIS`, `TARGET_VIVADO`) added to the synthesis defines | Bender 0.31 puts them on the simulation fileset only. `TARGET_FPGA` makes Ibex use its FPGA register file, as `fc_subsystem.sv` intends. CV32E40P doesn't use them. |
| `XPM_LIBRARIES` set on the project | All SoC memories (`tc_sram_xilinx`) are `xpm_memory_spram`; Vivado doesn't detect that with `-sfcu` and fails |
| Stops after `opt_design` (or routing with `IMPL=1`) | Area only; no bitstream |

The critical warning `overwriting previous definition of module
'pulp_clock_gating'` is expected: the Xilinx version from `target/`
replaces the generic one, as in the upstream flow. The others come from the
constraints (see Limits).

## Limits

- The numbers are for the FPGA. Shares differ a lot from an ASIC.
- The FPGA configuration includes every uDMA peripheral. That includes the
  HyperBus controller, although its pads are tied off; its logic stays in
  the design.
- Timing constraints: upstream's `nexys4DDR.xdc` refers to some instances
  by outdated names (e.g. `i_pulp_soc_i`), so Vivado reports about 15
  critical warnings and skips those constraints (ASYNC_REG, JTAG delays).
  This doesn't change the area; with `IMPL=1` the JTAG timing paths are less
  constrained than intended.
- No FP register file: PULPissimo builds CV32E40P with `USE_ZFINX=1`
  (floating-point values in the integer registers). The test programs are
  compiled for `rv32imfc`, but contain no floating-point instructions.
- These builds are for area only, not for programming the board: the boot
  ROM is the FPGA one, but nothing else is checked.
