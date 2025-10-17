//------------------------------------------------------------------------------
// trapezoid.sv  -- MF trapezowa: (a,b,c,d), we/wy jak w REQ-020
// Wejście x: Q7.0 (signed int8), wyjście mu: Q1.15 (unsigned)
//------------------------------------------------------------------------------
module trapezoid (
  input  logic              clk,
  input  logic signed [7:0] x,     // Q7.0
  input  logic signed [7:0] a, b, c, d, // Q7.0
  output logic       [15:0] mu     // Q1.15
);
  // Obliczenia „na skróty”, 1-cyklowe (możesz zpipelinić)
  always_comb begin
    mu = 16'd0;
    if (x <= a || x >= d) begin
      mu = 16'd0;
    end else if (x >= b && x <= c) begin
      mu = 16'd32767; // 1.0
    end else if (x > a && x < b) begin
      // (x-a)/(b-a) * 32767
      int num = (x - a);
      int den = (b - a);
      mu = (den != 0) ? ( (num * 32767) / den ) : 16'd0;
    end else if (x > c && x < d) begin
      int num = (d - x);
      int den = (d - c);
      mu = (den != 0) ? ( (num * 32767) / den ) : 16'd0;
    end
  end
endmodule
