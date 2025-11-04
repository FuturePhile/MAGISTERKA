// trapezoid.sv - membership function evaluator (trapezoid/triangle)
// REQ-020: trapezoidal MFs with parameters (a,b,c,d) in Q7.0
// REQ-210: internal fixed-point Q1.15 for mu
module trapezoid (
  input  logic signed [7:0] x,   // Q7.0
  input  logic signed [7:0] a,   // left foot
  input  logic signed [7:0] b,   // left shoulder / triangle peak (b=c)
  input  logic signed [7:0] c,   // right shoulder / triangle peak
  input  logic signed [7:0] d,   // right foot
  output logic        [15:0] mu  // Q1.15
);
  // Temporaries (minimal set)
  logic [8:0]  den;
  logic [8:0]  delta;
  logic [23:0] num_q15;

  always_comb begin
    // Defaults: keep combinational and safe divisors
    mu       = 16'd0;
    den      = 9'd1;
    delta    = 9'd0;
    num_q15  = 24'd0;

    // Piecewise trapezoid
    if ((x <= a) || (x >= d)) begin
      mu = 16'd0;
    end
    else if ((x >= b) && (x <= c)) begin
      mu = 16'h7FFF; // plateau approx 1.0
    end
    else if ((x > a) && (x < b)) begin
      // Left slope: (x - a) / (b - a)
      den     = $unsigned($signed(b) - $signed(a));
      den     = (den == 9'd0) ? 9'd1 : den;
      delta   = $unsigned($signed(x) - $signed(a));
      num_q15 = {delta, 15'd0};
      mu      = num_q15 / den;
    end
    else begin
      // Right slope: (d - x) / (d - c)
      den     = $unsigned($signed(d) - $signed(c));
      den     = (den == 9'd0) ? 9'd1 : den;
      delta   = $unsigned($signed(d) - $signed(x));
      num_q15 = {delta, 15'd0};
      mu      = num_q15 / den;
    end
  end
endmodule
