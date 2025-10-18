// trapezoid.sv — MF (trapez/triangle) Q7.0 -> Q1.15
// REQ: 020,210

module trapezoid(
  input  logic signed [7:0] x, a, b, c, d,
  output logic       [15:0] mu
);
  always_comb begin
    if (x <= a || x >= d)       mu = 16'd0;
    else if (x >= b && x <= c)  mu = 16'h7FFF;
    else if (x > a && x < b)    mu = ((x - a) <<< 15) / (b - a);
    else                        mu = ((d - x) <<< 15) / (d - c);
  end
endmodule
