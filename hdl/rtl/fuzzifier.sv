//------------------------------------------------------------------------------
// fuzzifier.sv -- 3 MF dla jednego wejścia (neg/zero/pos)  (REQ-020)
//------------------------------------------------------------------------------
module fuzzifier (
  input  logic              clk,
  input  logic signed [7:0] x,        // Q7.0
  // zestaw (a,b,c,d) dla neg/zero/pos
  input  logic signed [7:0] n_a, n_b, n_c, n_d,
  input  logic signed [7:0] z_a, z_b, z_c, z_d,
  input  logic signed [7:0] p_a, p_b, p_c, p_d,
  output logic       [15:0] mu_neg,   // Q1.15
  output logic       [15:0] mu_zero,
  output logic       [15:0] mu_pos
);
  trapezoid u_neg (.clk(clk), .x(x), .a(n_a), .b(n_b), .c(n_c), .d(n_d), .mu(mu_neg));
  trapezoid u_zero(.clk(clk), .x(x), .a(z_a), .b(z_b), .c(z_c), .d(z_d), .mu(mu_zero));
  trapezoid u_pos (.clk(clk), .x(x), .a(p_a), .b(p_b), .c(p_c), .d(p_d), .mu(mu_pos));
endmodule
