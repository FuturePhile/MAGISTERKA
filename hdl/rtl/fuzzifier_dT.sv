// REQ: 020
module fuzzifier_dT(
  input  logic signed [7:0] x,
  input  logic signed [7:0] a_neg,b_neg,c_neg,d_neg,
  input  logic signed [7:0] a_zero,b_zero,c_zero,d_zero,
  input  logic signed [7:0] a_pos,b_pos,c_pos,d_pos,
  output logic [15:0] mu_neg, mu_zero, mu_pos
);
  trapezoid u0 (.x(x), .a(a_neg),  .b(b_neg),  .c(c_neg),  .d(d_neg),  .mu(mu_neg));
  trapezoid u1 (.x(x), .a(a_zero), .b(b_zero), .c(czero),  .d(d_zero), .mu(mu_zero)); // TODO: czero->c_zero
  trapezoid u2 (.x(x), .a(a_pos),  .b(b_pos),  .c(c_pos),  .d(d_pos),  .mu(mu_pos));
endmodule
