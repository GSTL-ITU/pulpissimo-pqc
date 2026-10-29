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
make area IMPL=1             # also place & route: post-route numbers and timing, ~13 min
make compare IMPL=1          # both cores, post-route
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

## Results (Vivado 2026.1, post-route, `make compare IMPL=1`)

| | CV32E40P LUTs | FFs | BRAM | DSPs | Ibex LUTs | FFs | BRAM | DSPs |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Whole design** | 41,343 | 22,339 | 82 | 12 | 33,463 | 20,684 | 82 | 4 |
| **Core** | 7,302 | 2,660 | 0 | 7 | 3,181 | 1,387 | 0 | 1 |
| **FPU** (fpnew) | 3,666 | 382 | 0 | 2 | – | – | – | – |
| **SoC without core and FPU** | 30,375 | 19,297 | 82 | 3 | 30,282 | 19,297 | 82 | 3 |
| &nbsp;&nbsp;uDMA peripherals | 9,636 | 12,153 | 0 | 3 | 9,631 | 12,153 | 0 | 3 |
| &nbsp;&nbsp;interconnect | 5,050 | 1,044 | 0 | 0 | 4,972 | 1,044 | 0 | 0 |
| &nbsp;&nbsp;debug module and JTAG | 4,664 | 1,443 | 0 | 0 | 4,665 | 1,443 | 0 | 0 |
| &nbsp;&nbsp;event generator | 3,399 | 1,342 | 0 | 0 | 3,396 | 1,342 | 0 | 0 |
| &nbsp;&nbsp;pad frame (pad multiplexer) | 2,937 | 288 | 0 | 0 | 2,940 | 288 | 0 | 0 |
| &nbsp;&nbsp;GPIO | 1,445 | 482 | 0 | 0 | 1,437 | 482 | 0 | 0 |
| &nbsp;&nbsp;timers | 1,535 | 1,808 | 0 | 0 | 1,531 | 1,808 | 0 | 0 |
| &nbsp;&nbsp;other peripherals (APB bridge, `soc_ctrl`, ...) | 1,119 | 422 | 0 | 0 | 1,133 | 422 | 0 | 0 |
| &nbsp;&nbsp;rest of `fc_subsystem` (interrupt controller, ...) | 333 | 144 | 0 | 0 | 332 | 144 | 0 | 0 |
| &nbsp;&nbsp;L2 memory (320 KiB) | 54 | 0 | 80 | 0 | 55 | 0 | 80 | 0 |
| &nbsp;&nbsp;boot ROM, CDCs, APB decoder, glue | 203 | 171 | 2 | 0 | 190 | 171 | 2 | 0 |

Device usage (XC7A100T): CV32E40P 65.2% of the LUTs and 81.4% of the slices
(12,894 of 15,850), Ibex 52.8% of the LUTs and 73.0% of the slices (11,577);
both 61% of the block RAM (L2) and ~17% of the FFs. BRAM counts 36 Kb blocks.

**Post-route vs post-`opt_design`:** placement repacks logic, so routed LUT
counts are 3–4% lower (CV32E40P 41,343 vs 42,830; Ibex 33,463 vs 34,883;
cores 7,302 vs 7,418 and 3,181 vs 3,280). FFs, BRAM and DSPs are identical.
Without `IMPL=1` the flow stops after `opt_design` and gives those higher
numbers.

- **The SoC is identical** for both cores (to within 0.3%), as it should be;
  only the core and the FPU differ. CV32E40P without FPU: `make area USE_FPU=0`.
- **CV32E40P core: 7,302 LUTs**, of which the 31 × 32-bit flip-flop
  register file is 1,425 LUTs / 992 FFs. It includes the PULP extensions
  (`USE_XPULP=1`: hardware loops, post-increment loads, SIMD), which stock
  GCC doesn't use. 7 of its DSPs are the multiplier.
- **Ibex core: 3,181 LUTs**, with the LUT-RAM register file (109 LUTs, 44
  LUTRAM). Configuration from `fc_subsystem.sv`: RV32IMC with `RV32MFast`,
  10 performance counters, debug triggers, no PMP. That is the same
  configuration as the ibex-pqc demo system, whose core (a newer Ibex)
  has 3,311 LUTs and 1,369 FFs there (post-`opt_design`; 3,280 here at
  that stage).
- **The SoC dominates**: 73% of the LUTs with CV32E40P, 90% with Ibex. The
  biggest blocks are the uDMA peripherals (camera, filter, SDIO, HyperBus,
  I2C, QSPI, UART; the HyperBus controller alone is 2,766 LUTs / 4,817 FFs),
  the interconnect, the debug module and the event generator.

Per-block details, including the uDMA peripherals one by one, are in
`../build/fpga/<core>/area.md` and `../build/fpga/compare.md`.

### Timing (post-route)

| Clock | Period | CV32E40P setup slack (WNS) | Ibex WNS | Hold (WHS) |
|---|---:|---:|---:|---|
| SoC (`clk_out1_xilinx_clk_mngr`) | 100 ns (10 MHz) | 34.5 ns | 46.0 ns | **−0.27 / −0.23 ns, ~300 endpoints fail** |
| peripherals (`clk_out2`) | 200 ns (5 MHz) | 88.7 ns | 87.7 ns | met |
| slow clock | 32 kHz | 121 ns | 120 ns | met |
| JTAG `tck` | 100 ns | 13.2 ns | 12.1 ns | **−1.6 / −1.8 ns, 54 / 85 endpoints fail** |

Setup is met with a wide margin at the Nexys clocks. **Hold is not**, on
both cores. The cause is upstream's clock gating: `pulp_clock_gating_xilinx.sv`
(from `target/fpga/pulpissimo-nexys/rtl/`, used unchanged) is a latch and
an AND gate, so every gated clock (the core's sleep gate, the uDMA
peripherals, the timers, the camera pixel clock from the pad mux) leaves the
global clock network through a LUT. Vivado warns about it during placement
(`Place 30-568`: "A LUT ... is driving clock pin of 3802 registers. This
could lead to large hold time violations"), and the extra clock skew
(~2.3–2.7 ns on the worst paths) is more than the router can fix. Upstream's
own flow builds the same logic, so its bitstream has the same problem. The
area numbers are not affected; for a board bring-up this is the first thing
to look at (e.g. `BUFGCE`-based gating, or tying the gates open).

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
- Hold violations after routing, from upstream's LUT-based clock gating (see
  Timing above).
- No FP register file: PULPissimo builds CV32E40P with `USE_ZFINX=1`
  (floating-point values in the integer registers). The test programs are
  compiled for `rv32imfc`, but contain no floating-point instructions.
- These builds are for area only, not for programming the board: the boot
  ROM is the FPGA one, but nothing else is checked.
