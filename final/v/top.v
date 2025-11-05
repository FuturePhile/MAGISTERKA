// top.v - system top: MCU bus <-> mmio_if (shadow) <-> top_coprocessor (core)
module top (
  input         clk,
  input         rst_n,
  input         cs,
  input         rd,
  input         wr,
  input   [7:0] addr,
  input   [7:0] wdata,
  output  [7:0] rdata
);

  // Wires shadow <-> core
  wire        start;
  wire        init;
  wire        reg_mode;
  wire        dt_mode;
  wire signed [7:0] T_in;
  wire signed [7:0] dT_in;
  wire signed [7:0] T_neg_a;
  wire signed [7:0] T_neg_b;
  wire signed [7:0] T_neg_c;
  wire signed [7:0] T_neg_d;
  wire signed [7:0] T_zero_a;
  wire signed [7:0] T_zero_b;
  wire signed [7:0] T_zero_c;
  wire signed [7:0] T_zero_d;
  wire signed [7:0] T_pos_a;
  wire signed [7:0] T_pos_b;
  wire signed [7:0] T_pos_c;
  wire signed [7:0] T_pos_d;
  wire signed [7:0] dT_neg_a;
  wire signed [7:0] dT_neg_b;
  wire signed [7:0] dT_neg_c;
  wire signed [7:0] dT_neg_d;
  wire signed [7:0] dT_zero_a;
  wire signed [7:0] dT_zero_b;
  wire signed [7:0] dT_zero_c;
  wire signed [7:0] dT_zero_d;
  wire signed [7:0] dT_pos_a;
  wire signed [7:0] dT_pos_b;
  wire signed [7:0] dT_pos_c;
  wire signed [7:0] dT_pos_d;
  wire        valid;
  wire  [7:0] G_out;

  // Shadow MMIO
  mmio_if u_mmio_if (
    .clk(clk),
    .rst_n(rst_n),
    .cs(cs),
    .rd(rd),
    .wr(wr),
    .addr(addr),
    .wdata(wdata),
    .rdata(rdata),
    .start(start),
    .init(init),
    .reg_mode(reg_mode),
    .dt_mode(dt_mode),
    .T_in(T_in),
    .dT_in(dT_in),
    .T_neg_a(T_neg_a),
    .T_neg_b(T_neg_b),
    .T_neg_c(T_neg_c),
    .T_neg_d(T_neg_d),
    .T_zero_a(T_zero_a),
    .T_zero_b(T_zero_b),
    .T_zero_c(T_zero_c),
    .T_zero_d(T_zero_d),
    .T_pos_a(T_pos_a),
    .T_pos_b(T_pos_b),
    .T_pos_c(T_pos_c),
    .T_pos_d(T_pos_d),
    .dT_neg_a(dT_neg_a),
    .dT_neg_b(dT_neg_b),
    .dT_neg_c(dT_neg_c),
    .dT_neg_d(dT_neg_d),
    .dT_zero_a(dT_zero_a),
    .dT_zero_b(dT_zero_b),
    .dT_zero_c(dT_zero_c),
    .dT_zero_d(dT_zero_d),
    .dT_pos_a(dT_pos_a),
    .dT_pos_b(dT_pos_b),
    .dT_pos_c(dT_pos_c),
    .dT_pos_d(dT_pos_d),
    .valid(valid),
    .G_out(G_out)
  );

  // Coprocessor core
  top_coprocessor u_top_coprocessor (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .init(init),
    .reg_mode(reg_mode),
    .dt_mode(dt_mode),
    .T_in(T_in),
    .dT_in(dT_in),
    .T_neg_a(T_neg_a),
    .T_neg_b(T_neg_b),
    .T_neg_c(T_neg_c),
    .T_neg_d(T_neg_d),
    .T_zero_a(T_zero_a),
    .T_zero_b(T_zero_b),
    .T_zero_c(T_zero_c),
    .T_zero_d(T_zero_d),
    .T_pos_a(T_pos_a),
    .T_pos_b(T_pos_b),
    .T_pos_c(T_pos_c),
    .T_pos_d(T_pos_d),
    .dT_neg_a(dT_neg_a),
    .dT_neg_b(dT_neg_b),
    .dT_neg_c(dT_neg_c),
    .dT_neg_d(dT_neg_d),
    .dT_zero_a(dT_zero_a),
    .dT_zero_b(dT_zero_b),
    .dT_zero_c(dT_zero_c),
    .dT_zero_d(dT_zero_d),
    .dT_pos_a(dT_pos_a),
    .dT_pos_b(dT_pos_b),
    .dT_pos_c(dT_pos_c),
    .dT_pos_d(dT_pos_d),
    .valid(valid),
    .G_out(G_out)
  );

endmodule
