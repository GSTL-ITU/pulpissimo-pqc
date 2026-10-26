// PULPissimo testbench for Verilator
//
// Unlike target/sim/tb/tb_pulp_simple.sv this testbench does not boot through
// JTAG (the JTAG TB packages rely on simulator features Verilator lacks).
// Instead it:
//   1. preloads L2 through backdoor writes into the SRAM models while the SoC
//      is held in reset,
//   2. overrides the FC boot address with the program entry point,
//   3. releases reset and waits for the program to write CORESTATUS (this is
//      what exit()/return from main() does in pulp-runtime),
//   4. ends the simulation with $finish (exit code 0) on success or $fatal
//      (non-zero exit code) on failure/timeout.
//
// printf() output reaches the console through the SIM_STDOUT virtual
// peripheral inside pulp_soc.
//
// Plusargs:
//   +MEM=<file>          Memory image from elf2mem.py (required)
//   +TIMEOUT_US=<n>      Simulated-time timeout in microseconds (default 100000)
//   +WAVES=<file.fst>    Dump an FST waveform to <file.fst>

`timescale 1ns/1ps

module tb_verilator #(
  // 0: CV32E40P (RI5CY), 1: Ibex RV32IMC, 2: Ibex RV32EC
  parameter int unsigned CORE_TYPE = 0,
  parameter bit          USE_FPU   = 1,
  parameter bit          USE_ZFINX = 0
);

  localparam time         REF_CLK_HALF_PERIOD = 15258ns; // ~32.768 kHz
  localparam int unsigned IO_PAD_COUNT        = gpio_reg_pkg::GPIOCount;

  // L2 layout, see pulp_soc/rtl/pulp_soc/l2_ram_multi_bank.sv and
  // hw/includes/soc_mem_map.svh
  localparam logic [31:0] L2_PRI0_START = 32'h1C00_0000;
  localparam logic [31:0] L2_PRI1_START = 32'h1C00_8000;
  localparam logic [31:0] L2_INTL_START = 32'h1C01_0000;
  localparam logic [31:0] L2_INTL_END   = 32'h1C09_0000;

  /////////////////////////
  // Clock, reset, pads //
  /////////////////////////

  logic s_ref_clk = 1'b0;
  logic s_rst_n   = 1'b0;

  always #(REF_CLK_HALF_PERIOD) s_ref_clk = ~s_ref_clk;

  // All pads are inout, so they must be connected to wires (not constants)
  wire                    w_pad_ref_clk;
  wire                    w_pad_reset_n;
  wire                    w_pad_clk_byp_en;
  wire                    w_pad_bootsel0;
  wire                    w_pad_bootsel1;
  wire                    w_pad_jtag_tck;
  wire                    w_pad_jtag_tdi;
  wire                    w_pad_jtag_tms;
  wire                    w_pad_jtag_trstn;
  wire                    w_pad_jtag_tdo;
  wire [1:0]              w_pad_hyper_csn;
  wire                    w_pad_hyper_reset_n;
  wire                    w_pad_hyper_ck;
  wire                    w_pad_hyper_ckn;
  wire [7:0]              w_pad_hyper_dq;
  wire                    w_pad_hyper_rwds;
  wire [IO_PAD_COUNT-1:0] w_pad_io;

  assign w_pad_ref_clk    = s_ref_clk;
  assign w_pad_reset_n    = s_rst_n;
  assign w_pad_clk_byp_en = 1'b0;
  // bootsel = 3: "preloaded" boot. The bootrom is skipped anyway since the
  // boot address is overridden below.
  assign w_pad_bootsel0   = 1'b1;
  assign w_pad_bootsel1   = 1'b1;
  // JTAG is unused, keep the TAP in reset
  assign w_pad_jtag_tck   = 1'b0;
  assign w_pad_jtag_tdi   = 1'b0;
  assign w_pad_jtag_tms   = 1'b0;
  assign w_pad_jtag_trstn = 1'b0;

  /////////
  // DUT //
  /////////

  pulpissimo #(
    .CORE_TYPE  ( CORE_TYPE ),
    .USE_FPU    ( USE_FPU   ),
    .USE_ZFINX  ( USE_ZFINX ),
    .USE_HWPE   ( 1'b0      ),
    .SIM_STDOUT ( 1'b1      )
  ) i_dut (
    .pad_ref_clk       ( w_pad_ref_clk       ),
    .pad_reset_n       ( w_pad_reset_n       ),
    .pad_clk_byp_en    ( w_pad_clk_byp_en    ),
    .pad_bootsel0      ( w_pad_bootsel0      ),
    .pad_bootsel1      ( w_pad_bootsel1      ),
    .pad_jtag_tck      ( w_pad_jtag_tck      ),
    .pad_jtag_tdi      ( w_pad_jtag_tdi      ),
    .pad_jtag_tdo      ( w_pad_jtag_tdo      ),
    .pad_jtag_tms      ( w_pad_jtag_tms      ),
    .pad_jtag_trstn    ( w_pad_jtag_trstn    ),
    .pad_hyper_csn     ( w_pad_hyper_csn     ),
    .pad_hyper_reset_n ( w_pad_hyper_reset_n ),
    .pad_hyper_ck      ( w_pad_hyper_ck      ),
    .pad_hyper_ckn     ( w_pad_hyper_ckn     ),
    .pad_hyper_dq      ( w_pad_hyper_dq      ),
    .pad_hyper_rwds    ( w_pad_hyper_rwds    ),
    .pad_io            ( w_pad_io            )
  );

  ////////////////////
  // L2 preloading //
  ////////////////////

  task automatic l2_write(input logic [31:0] addr, input logic [31:0] data);
    logic [31:0] off;
    if (addr >= L2_PRI0_START && addr < L2_PRI1_START) begin
      off = (addr - L2_PRI0_START) >> 2;
      i_dut.i_soc_domain.i_pulp_soc.l2_ram_i.bank_sram_pri0_i.sram[off[12:0]] = data;
    end else if (addr >= L2_PRI1_START && addr < L2_INTL_START) begin
      off = (addr - L2_PRI1_START) >> 2;
      i_dut.i_soc_domain.i_pulp_soc.l2_ram_i.bank_sram_pri1_i.sram[off[12:0]] = data;
    end else if (addr >= L2_INTL_START && addr < L2_INTL_END) begin
      // 4 word-interleaved banks: bank = addr[3:2], row = addr[17:4]
      off = addr - L2_INTL_START;
      case (off[3:2])
        2'd0: i_dut.i_soc_domain.i_pulp_soc.l2_ram_i.CUTS[0].bank_i.sram[off[17:4]] = data;
        2'd1: i_dut.i_soc_domain.i_pulp_soc.l2_ram_i.CUTS[1].bank_i.sram[off[17:4]] = data;
        2'd2: i_dut.i_soc_domain.i_pulp_soc.l2_ram_i.CUTS[2].bank_i.sram[off[17:4]] = data;
        2'd3: i_dut.i_soc_domain.i_pulp_soc.l2_ram_i.CUTS[3].bank_i.sram[off[17:4]] = data;
      endcase
    end else begin
      $fatal(1, "[TB] Address 0x%08h of the memory image is outside of L2", addr);
    end
  endtask

  // File format (written by elf2mem.py): first line is the entry point, then
  // one "<addr> <data>" pair per 32-bit word, all in hex.
  task automatic load_mem_image(input string path, output logic [31:0] entry);
    int          fd, n, words;
    logic [31:0] addr, data;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "[TB] Cannot open memory image %s", path);
    if ($fscanf(fd, "%h\n", entry) != 1) $fatal(1, "[TB] Malformed memory image %s", path);
    words = 0;
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%h %h\n", addr, data);
      if (n != 2) break;
      l2_write(addr, data);
      words++;
    end
    $fclose(fd);
    $display("[TB] Loaded %0d words from %s, entry point 0x%08h", words, path, entry);
  endtask

  ///////////////
  // Main flow //
  ///////////////

  logic [31:0] entry_point = '0;

  // Boot straight into the program instead of the bootrom
  initial force i_dut.i_soc_domain.i_pulp_soc.s_fc_bootaddr = entry_point;

  wire        s_eoc       = i_dut.i_soc_domain.i_pulp_soc.soc_peripherals_i.s_soc_ctrl_reg_reg2hw.corestatus.eoc.q;
  wire [30:0] s_exit_code = i_dut.i_soc_domain.i_pulp_soc.soc_peripherals_i.s_soc_ctrl_reg_reg2hw.corestatus.exit_code.q;

  initial begin : main
    string       mem_file, waves_file;
    longint      timeout_us;

    if (!$value$plusargs("MEM=%s", mem_file))
      $fatal(1, "[TB] +MEM=<memory image> is required");
    if (!$value$plusargs("TIMEOUT_US=%d", timeout_us))
      timeout_us = 100000;
    if ($value$plusargs("WAVES=%s", waves_file)) begin
      $dumpfile(waves_file);
      $dumpvars(0, tb_verilator);
    end

    $timeformat(-6, 3, " us", 0);

    // Let the SRAM models settle before backdoor-loading them
    #1ns;
    load_mem_image(mem_file, entry_point);

    #(REF_CLK_HALF_PERIOD * 10);
    s_rst_n = 1'b1;
    $display("[TB] %t: Reset released", $time);

    fork
      begin
        wait (s_eoc === 1'b1);
      end
      begin
        #(timeout_us * 1us);
        $fatal(1, "[TB] %t: TIMEOUT after %0d us without the program exiting", $time, timeout_us);
      end
    join_any

    if (s_exit_code == 0) begin
      $display("[TB] %t: PASSED (exit code 0)", $time);
      $finish;
    end else begin
      $fatal(1, "[TB] %t: FAILED (exit code %0d)", $time, s_exit_code);
    end
  end

endmodule
