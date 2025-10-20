// rules4.sv — 4-corner rule set, w = min(μ_T, μ_dT)
// REQ: 030,040
module rules4 (
  // μ in Q1.15 (non-negative)
  input  logic [15:0] muT_neg,
  input  logic [15:0] muT_pos,
  input  logic [15:0] muD_neg,
  input  logic [15:0] muD_pos,
  // outputs (weights, Q1.15)
  output logic [15:0] w_nn, // (T.neg, dT.neg)
  output logic [15:0] w_np, // (T.neg, dT.pos)
  output logic [15:0] w_pn, // (T.pos, dT.neg)
  output logic [15:0] w_pp  // (T.pos, dT.pos)
);

  // min for Q1.15 magnitudes (unsigned domain is fine; μ ≥ 0)
  function automatic logic [15:0] fmin (
    input logic [15:0] a,
    input logic [15:0] b
  );
    return (a < b) ? a : b;
  endfunction

  always_comb begin
    w_nn = fmin(muT_neg, muD_neg);
    w_np = fmin(muT_neg, muD_pos);
    w_pn = fmin(muT_pos, muD_neg);
    w_pp = fmin(muT_pos, muD_pos);
  end
endmodule
