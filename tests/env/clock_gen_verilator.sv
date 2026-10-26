// Replacement (for Verilator) of hw/clock_gen_generic.sv
//
// The generic clock_gen instantiates the gf22_FLL behavioural model, which is
// written in VHDL and therefore cannot be compiled by Verilator. Bender.yml
// already drops clock_gen_generic.sv for the `verilator` target; this module
// fills that slot with the same interface:
//
// * soc_clk_o / per_clk_o are free-running clocks at a fixed frequency
//   (~50 MHz, matching the FLL reset configuration seen by the runtime).
// * The FLL configuration interface is kept (apb_to_fll) and backed by a small
//   register stub, so software that programs the FLLs (pulp-runtime does this
//   at boot) reads back sensible values and never blocks.

`timescale 1ns/1ps

module clock_gen #(
  parameter int unsigned  APB_ADDR_WIDTH,
  localparam int unsigned APB_DATA_WIDTH = 32
)(
  input logic  ref_clk_i,

  input logic  rst_ni,

  input logic  dft_test_en_i,

  input logic  cfg_clk_i,
  APB.Slave    cfg_bus_slave,

  input logic  slow_clk_en_i,
  input logic  slow_clk_byp_en_i, // feed slow_clk_o directly from ref_clk_i,
  output logic slow_clk_o,
  input logic  soc_clk_en_i,
  input logic  soc_clk_byp_en_i,
  output logic soc_clk_o,

  input logic  per_clk_en_i,
  input logic  per_clk_byp_en_i,
  output logic per_clk_o
);

  // FLL reset values (see sw/pulp-runtime/include/archi/fll/fll_v1.h).
  // mult_factor=0x5f5 with a 32.768 kHz reference gives ~50 MHz.
  localparam logic [31:0] FLL_CONF1_RESET = 32'h0000_05f5 | (32'h121 << 16) | (32'h1 << 26) | (32'h1 << 30);
  localparam logic [31:0] FLL_CONF2_RESET = 32'h9 | (32'h10 << 4) | (32'h10 << 10) | (32'h200 << 16) | (32'h1 << 29);
  localparam time         SOC_CLK_HALF_PERIOD = 10ns;
  localparam time         PER_CLK_HALF_PERIOD = 10ns;

  logic        s_clk_fll_soc = 1'b0;
  logic        s_clk_soc_ungated;
  logic        s_clk_fll_per = 1'b0;
  logic        s_clk_per_ungated;

  always #(SOC_CLK_HALF_PERIOD) s_clk_fll_soc = ~s_clk_fll_soc;
  always #(PER_CLK_HALF_PERIOD) s_clk_fll_per = ~s_clk_fll_per;

  FLL_BUS fll_bus[2](.clk_i(cfg_clk_i));

  apb_to_fll #(
    .APB_ADDR_WIDTH(APB_ADDR_WIDTH),
    .NR_FLLS(2)
  ) apb2fll_if_i (
    .clk_i    ( cfg_clk_i     ),
    .rst_ni,
    .apb      ( cfg_bus_slave ),
    .fll_intf ( fll_bus       )
  );

  // FLL register stub. Register map (CFGAD): 0 status, 1 conf1, 2 conf2,
  // 3 integrator. The status register reports the requested mult factor, i.e.
  // the FLL appears to be locked immediately.
  for (genvar i = 0; i < 2; i++) begin : gen_fll_stub
    logic [31:0] conf1_q, conf2_q, integrator_q, rdata_q;
    logic        req_q;

    assign fll_bus[i].ack   = req_q;
    assign fll_bus[i].lock  = 1'b1;
    assign fll_bus[i].rdata = rdata_q;

    always_ff @(posedge cfg_clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        conf1_q      <= FLL_CONF1_RESET;
        conf2_q      <= FLL_CONF2_RESET;
        integrator_q <= '0;
        rdata_q      <= '0;
        req_q        <= 1'b0;
      end else begin
        req_q <= fll_bus[i].req;
        // apb_to_fll only drives addr/wdata while req is high, so sample then
        if (fll_bus[i].req && !req_q) begin
          if (!fll_bus[i].wrn) begin
            case (fll_bus[i].addr)
              2'd1: conf1_q      <= fll_bus[i].wdata;
              2'd2: conf2_q      <= fll_bus[i].wdata;
              2'd3: integrator_q <= fll_bus[i].wdata;
              default: ;
            endcase
          end
          case (fll_bus[i].addr)
            2'd0:    rdata_q <= {16'h0, conf1_q[15:0]};
            2'd1:    rdata_q <= conf1_q;
            2'd2:    rdata_q <= conf2_q;
            default: rdata_q <= integrator_q;
          endcase
        end
      end
    end
  end

  tc_clk_mux2 i_fll_soc_bypass_mux (
    .clk0_i    ( s_clk_fll_soc     ),
    .clk1_i    ( ref_clk_i         ),
    .clk_sel_i ( soc_clk_byp_en_i  ),
    .clk_o     ( s_clk_soc_ungated )
  );

  tc_clk_gating #(.IS_FUNCTIONAL(1'b1)) i_soc_clk_en(
    .clk_i     ( s_clk_soc_ungated ),
    .en_i      ( soc_clk_en_i      ),
    .test_en_i ( dft_test_en_i     ),
    .clk_o     ( soc_clk_o         )
  );

  tc_clk_mux2 i_fll_per_bypass_mux (
    .clk0_i    ( s_clk_fll_per     ),
    .clk1_i    ( ref_clk_i         ),
    .clk_sel_i ( per_clk_byp_en_i  ),
    .clk_o     ( s_clk_per_ungated )
  );

  tc_clk_gating #(.IS_FUNCTIONAL(1'b1)) i_per_clk_en(
    .clk_i     ( s_clk_per_ungated ),
    .en_i      ( per_clk_en_i      ),
    .test_en_i ( dft_test_en_i     ),
    .clk_o     ( per_clk_o         )
  );

  tc_clk_gating #(.IS_FUNCTIONAL(1'b1)) i_slow_clk_en(
    .clk_i     ( ref_clk_i     ),
    .en_i      ( slow_clk_en_i ),
    .test_en_i ( dft_test_en_i ),
    .clk_o     ( slow_clk_o    )
  );

endmodule
