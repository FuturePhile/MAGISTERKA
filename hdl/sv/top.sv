// top.sv - system top: MCU bus <-> mmio_if (shadow) <-> top_coprocessor (core)
module top (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        cs,
  input  logic        rd,
  input  logic        wr,
  input  logic  [7:0] addr,
  input  logic  [7:0] wdata,
  output logic  [7:0] rdata
);

  // Wires shadow <-> core
  logic        start;
  logic        init;
  logic        reg_mode;
  logic        dt_mode;
  logic signed [7:0] T_in;
  logic signed [7:0] dT_in;
  logic signed [7:0] T_neg_a;
  logic signed [7:0] T_neg_b;
  logic signed [7:0] T_neg_c;
  logic signed [7:0] T_neg_d;
  logic signed [7:0] T_zero_a;
  logic signed [7:0] T_zero_b;
  logic signed [7:0] T_zero_c;
  logic signed [7:0] T_zero_d;
  logic signed [7:0] T_pos_a;
  logic signed [7:0] T_pos_b;
  logic signed [7:0] T_pos_c;
  logic signed [7:0] T_pos_d;
  logic signed [7:0] dT_neg_a;
  logic signed [7:0] dT_neg_b;
  logic signed [7:0] dT_neg_c;
  logic signed [7:0] dT_neg_d;
  logic signed [7:0] dT_zero_a;
  logic signed [7:0] dT_zero_b;
  logic signed [7:0] dT_zero_c;
  logic signed [7:0] dT_zero_d;
  logic signed [7:0] dT_pos_a;
  logic signed [7:0] dT_pos_b;
  logic signed [7:0] dT_pos_c;
  logic signed [7:0] dT_pos_d;
  logic        valid;
  logic  [7:0] G_out;

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
