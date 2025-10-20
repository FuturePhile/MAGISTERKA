// rules9.sv — full 3x3 rule grid, w = min( μ_T[i], μ_dT[j] )
// REQ-030: 9 rules variant
// REQ-040: membership to weights via min()
module rules9 (
  input  logic [15:0] muT_neg,
  input  logic [15:0] muT_zero,
  input  logic [15:0] muT_pos,
  input  logic [15:0] muD_neg,
  input  logic [15:0] muD_zero,
  input  logic [15:0] muD_pos,
  output logic [15:0] w00, // (neg,neg)
  output logic [15:0] w01, // (neg,zero)
  output logic [15:0] w02, // (neg,pos)
  output logic [15:0] w10, // (zero,neg)
  output logic [15:0] w11, // (zero,zero)
  output logic [15:0] w12, // (zero,pos)
  output logic [15:0] w20, // (pos,neg)
  output logic [15:0] w21, // (pos,zero)
  output logic [15:0] w22  // (pos,pos)
);
  function automatic [15:0] fmin (
    input logic [15:0] a, 
    input logic [15:0] b
    );
    fmin = (a < b) ? a : b;
  endfunction

  always_comb begin
    w00 = fmin(muT_neg , muD_neg );
    w01 = fmin(muT_neg , muD_zero);
    w02 = fmin(muT_neg , muD_pos );
    w10 = fmin(muT_zero, muD_neg );
    w11 = fmin(muT_zero, muD_zero);
    w12 = fmin(muT_zero, muD_pos );
    w20 = fmin(muT_pos , muD_neg );
    w21 = fmin(muT_pos , muD_zero);
    w22 = fmin(muT_pos , muD_pos );
  end
endmodule
