// rules9.v - full 3x3 rule grid, w = min(mu_T[i], mu_dT[j])
// REQ-030: 9 rules variant
// REQ-040: membership to weights via min()
module rules9 (
  input  [15:0] muT_neg,
  input  [15:0] muT_zero,
  input  [15:0] muT_pos,
  input  [15:0] muD_neg,
  input  [15:0] muD_zero,
  input  [15:0] muD_pos,
  output [15:0] w00,  // (neg,neg)
  output [15:0] w01,  // (neg,zero)
  output [15:0] w02,  // (neg,pos)
  output [15:0] w10,  // (zero,neg)
  output [15:0] w11,  // (zero,zero)
  output [15:0] w12,  // (zero,pos)
  output [15:0] w20,  // (pos,neg)
  output [15:0] w21,  // (pos,zero)
  output [15:0] w22   // (pos,pos)
);

  function [15:0] fmin;
    input [15:0] a;
    input [15:0] b;
    begin
      if (a < b) fmin = a; else fmin = b;
    end
  endfunction

  assign w00 = fmin(muT_neg , muD_neg );
  assign w01 = fmin(muT_neg , muD_zero);
  assign w02 = fmin(muT_neg , muD_pos );
  assign w10 = fmin(muT_zero, muD_neg );
  assign w11 = fmin(muT_zero, muD_zero);
  assign w12 = fmin(muT_zero, muD_pos );
  assign w20 = fmin(muT_pos , muD_neg );
  assign w21 = fmin(muT_pos , muD_zero);
  assign w22 = fmin(muT_pos , muD_pos );

endmodule
