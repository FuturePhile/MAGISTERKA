// fuzzifier_dT.sv - three trapezoidal membership functions for dT: {neg, zero, pos}
// REQ-020: configurable (a,b,c,d) per set, mu outputs in Q1.15
module fuzzifier_dT (
  input  logic signed [7:0] x,
  input  logic signed [7:0] a_neg,
  input  logic signed [7:0] b_neg,
  input  logic signed [7:0] c_neg,
  input  logic signed [7:0] d_neg,
  input  logic signed [7:0] a_zero,
  input  logic signed [7:0] b_zero,
  input  logic signed [7:0] c_zero,
  input  logic signed [7:0] d_zero,
  input  logic signed [7:0] a_pos,
  input  logic signed [7:0] b_pos,
  input  logic signed [7:0] c_pos,
  input  logic signed [7:0] d_pos,
  output logic        [15:0] mu_neg,   // Q1.15
  output logic        [15:0] mu_zero,  // Q1.15
  output logic        [15:0] mu_pos    // Q1.15
);

  trapezoid u_neg  (.x(x), .a(a_neg),  .b(b_neg),  .c(c_neg),  .d(d_neg),  .mu(mu_neg));
  trapezoid u_zero (.x(x), .a(a_zero), .b(b_zero), .c(c_zero), .d(d_zero), .mu(mu_zero));
  trapezoid u_pos  (.x(x), .a(a_pos),  .b(b_pos),  .c(c_pos),  .d(d_pos),  .mu(mu_pos));

endmodule
