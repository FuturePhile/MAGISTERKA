// trapezoid.sv — membership function evaluator (trapezoid/triangle)
// REQ-020: trapezoidal MFs with parameters (a,b,c,d) in Q7.0
// REQ-210: internal fixed-point Q1.15 for μ
module trapezoid (
  input  logic signed [7:0] x,   // input value (Q7.0)
  input  logic signed [7:0] a,   // left foot
  input  logic signed [7:0] b,   // left shoulder / triangle peak (b=c)
  input  logic signed [7:0] c,   // right shoulder / triangle peak
  input  logic signed [7:0] d,   // right foot
  output logic        [15:0] mu  // membership μ in Q1.15 (0..1)
);
  // NOTE: For now we use division by variable denominators (synthesizable but heavy).
  // Later we can replace with a small sequential divider or reciprocal trick if timing/resources require.
  // Q7.0 → Q1.15; safe widths and guards
  logic [8:0] xb, xa;
  logic [8:0] dx1, dx2;
  logic [8:0] den1, den2;
  logic [15:0] num1, num2;

  always_comb begin
    mu = 16'd0; // default

    if ((x <= a) || (x >= d)) begin
      mu = 16'd0; // outside support
    end
    else if ((x >= b) && (x <= c)) begin
      mu = 16'h7FFF; // plateau
    end
    else if ((x > a) && (x < b)) begin
      // left slope segment: (x-a)/(b-a)
      dx1  = $unsigned($signed(b) - $signed(a));    // 0..255 → 9b
      xb   = $unsigned($signed(x) - $signed(a));    // 0..(b-a)
      den1 = (dx1 == 9'd0) ? 9'd1 : dx1;            // guard /0
      num1 = {xb[7:0], 7'd0};                       // (x-a) << 7 -> Q8.7
      mu   = (num1 << 8) / den1;                    // -> Q1.15
    end
    else begin
      // right slope segment: (d-x)/(d-c)
      dx2  = $unsigned($signed(d) - $signed(c));    // 0..255
      xa   = $unsigned($signed(d) - $signed(x));    // 0..(d-c)
      den2 = (dx2 == 9'd0) ? 9'd1 : dx2;
      num2 = {xa[7:0], 7'd0};
      mu   = (num2 << 8) / den2;
    end
  end

endmodule
