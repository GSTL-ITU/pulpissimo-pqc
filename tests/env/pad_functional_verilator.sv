// Replacement (for Verilator) of tech_cells_generic/src/deprecated/pad_functional.sv
//
// The original models the pull resistors with switch-level primitives (rpmos),
// which Verilator does not support. Here the pull is always present; it only
// matters for pads nobody drives.

module pad_functional_pd (
  input  logic OEN,
  input  logic I,
  output logic O,
  input  logic PEN,
  inout  wire  PAD
);
  assign PAD = OEN ? 1'bz : I;
  pulldown (PAD);
  assign O = PAD;
endmodule

module pad_functional_pu (
  input  logic OEN,
  input  logic I,
  output logic O,
  input  logic PEN,
  inout  wire  PAD
);
  assign PAD = OEN ? 1'bz : I;
  pullup (PAD);
  assign O = PAD;
endmodule
