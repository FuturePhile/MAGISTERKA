// trapezoid.sv — membership function evaluator (trapezoid/triangle)
// REQ-020: trapezoidal MFs with parameters (a,b,c,d) in Q7.0
// REQ-210: internal fixed-point Q1.15 for μ
module trapezoid (
  input  logic signed [7:0] x,   // Q7.0
  input  logic signed [7:0] a,
  input  logic signed [7:0] b,
  input  logic signed [7:0] c,
  input  logic signed [7:0] d,
  output logic        [15:0] mu  // Q1.15
);
  // temps
  logic [8:0]  xb, xa;
  logic [8:0]  dx1, dx2;
  logic [8:0]  den1, den2;
  logic [15:0] num1, num2;
  logic [23:0] num1_q15, num2_q15;

  always_comb begin
    // -------- defaults to keep the block purely combinational --------
    mu        = 16'd0;
    xb        = '0;   xa        = '0;
    dx1       = '0;   dx2       = '0;
    den1      = 9'd1; den2      = 9'd1;   // safe non-zero denominators
    num1      = '0;   num2      = '0;
    num1_q15  = '0;   num2_q15  = '0;

    // -------- piecewise trapezoid --------
    if ((x <= a) || (x >= d)) begin
      // outside support -> mu = 0 (already)
    end
    else if ((x >= b) && (x <= c)) begin
      mu = 16'h7FFF;                    // plateau ~1.0
    end
    else if ((x > a) && (x < b)) begin
      // left slope: (x-a)/(b-a)
      dx1      = $unsigned($signed(b) - $signed(a));
      xb       = $unsigned($signed(x) - $signed(a));
      den1     = (dx1 == 9'd0) ? 9'd1 : dx1;
      num1     = {xb[7:0], 7'd0};       // Q8.7
      num1_q15 = {8'd0, num1} << 8;     // -> Q1.15
      mu       = num1_q15 / den1;       // trunc to Q1.15
    end
    else begin
      // right slope: (d-x)/(d-c)
      dx2      = $unsigned($signed(d) - $signed(c));
      xa       = $unsigned($signed(d) - $signed(x));
      den2     = (dx2 == 9'd0) ? 9'd1 : dx2;
      num2     = {xa[7:0], 7'd0};       // Q8.7
      num2_q15 = {8'd0, num2} << 8;     // -> Q1.15
      mu       = num2_q15 / den2;
    end
  end
endmodule
