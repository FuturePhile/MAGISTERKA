// aggregator.sv — sums S_w and S_wg with g_ij given in percent
// REQ-040: Σw_ij and Σ(w_ij * g_ij)
// REQ-050: supports both 4-rule ("corners only") and 9-rule mode
// REQ-210: fixed-point Q1.15 internally
module aggregator (
  input  logic        reg_mode, // 0: corners only, 1: full 3x3
  // weights
  input  logic [15:0] w00, w01, w02,
  input  logic [15:0] w10, w11, w12,
  input  logic [15:0] w20, w21, w22,
  // singletons in %
  input  logic [7:0]  g00, g01, g02,
  input  logic [7:0]  g10, g11, g12,
  input  logic [7:0]  g20, g21, g22,
  // outputs
  output logic [15:0] S_w,   // Σw (Q1.15)
  output logic [15:0] S_wg   // Σ(w*g) (Q1.15)
);
  // Convert percent (0..100) to Q1.15: *32768/100
  function automatic [15:0] g2q15 (input [7:0] g);
    g2q15 = (g * 16'd32768) / 16'd100;
  endfunction

  // Gate center/edge weights in 4-rule mode
  logic [15:0] w01s, w10s, w11s, w12s, w21s;
  always_comb begin
    w01s = reg_mode ? w01 : 16'd0;
    w10s = reg_mode ? w10 : 16'd0;
    w11s = reg_mode ? w11 : 16'd0;
    w12s = reg_mode ? w12 : 16'd0;
    w21s = reg_mode ? w21 : 16'd0;
  end

  // Weighted terms (Q1.15 * Q1.15 >> 15 = Q1.15)
  logic [15:0] gw00,gw01,gw02,gw10,gw11,gw12,gw20,gw21,gw22;
  always_comb begin
    gw00 = (w00 * g2q15(g00)) >> 15;
    gw01 = (w01s* g2q15(g01)) >> 15;
    gw02 = (w02 * g2q15(g02)) >> 15;
    gw10 = (w10s* g2q15(g10)) >> 15;
    gw11 = (w11s* g2q15(g11)) >> 15;
    gw12 = (w12s* g2q15(g12)) >> 15;
    gw20 = (w20 * g2q15(g20)) >> 15;
    gw21 = (w21s* g2q15(g21)) >> 15;
    gw22 = (w22 * g2q15(g22)) >> 15;
  end

  always_comb begin
    S_w  = w00 + w02 + w20 + w22 + w01s + w10s + w11s + w12s + w21s;
    S_wg = gw00+ gw02+ gw20+ gw22+ gw01 + gw10 + gw11 + gw12 + gw21;
  end
endmodule
