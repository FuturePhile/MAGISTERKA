// aggregator.sv - sums S_w and S_wg with g_ij given in percent
// REQ-040: sum of w_ij and sum of (w_ij * g_ij)
// REQ-050: supports both 4-rule (corners only) and 9-rule mode
// REQ-210: fixed-point Q1.15 internally
module aggregator (
  input  logic        reg_mode,  // 0: corners only, 1: full 3x3
  input  logic [15:0] w00,
  input  logic [15:0] w01,
  input  logic [15:0] w02,
  input  logic [15:0] w10,
  input  logic [15:0] w11,
  input  logic [15:0] w12,
  input  logic [15:0] w20,
  input  logic [15:0] w21,
  input  logic [15:0] w22,
  input  logic  [7:0] g00,       // percent 0..100
  input  logic  [7:0] g01,
  input  logic  [7:0] g02,
  input  logic  [7:0] g10,
  input  logic  [7:0] g11,
  input  logic  [7:0] g12,
  input  logic  [7:0] g20,
  input  logic  [7:0] g21,
  input  logic  [7:0] g22,
  output logic [15:0] S_w,       // Q1.15
  output logic [15:0] S_wg       // Q1.15
);

  // Percent (0..100) to Q1.15 (0..32767) with rounding and clamp
  function automatic [15:0] g2q15(input logic [7:0] gpct);
    logic [31:0] tmp;
    begin
      tmp   = (gpct * 32'd32767) + 32'd50;
      tmp   = tmp / 32'd100;
      g2q15 = (tmp > 32'd32767) ? 16'd32767 : tmp[15:0];
    end
  endfunction

  // Helper: Q1.15 * Q1.15 -> Q1.15 with rounding
  localparam logic [31:0] HALF_LSB_15 = 32'd1 << 14;
  function automatic [15:0] mul_q15(input logic [15:0] w, input logic [15:0] gq15);
    begin
      mul_q15 = (((w * gq15) + HALF_LSB_15) >> 15);
    end
  endfunction

  // Gate center/edge weights in 4-rule mode
  logic [15:0] w01s;
  logic [15:0] w10s;
  logic [15:0] w11s;
  logic [15:0] w12s;
  logic [15:0] w21s;
  assign w01s = reg_mode ? w01 : 16'd0;
  assign w10s = reg_mode ? w10 : 16'd0;
  assign w11s = reg_mode ? w11 : 16'd0;
  assign w12s = reg_mode ? w12 : 16'd0;
  assign w21s = reg_mode ? w21 : 16'd0;

  // Precompute g in Q1.15
  logic [15:0] g00_q15;
  logic [15:0] g01_q15;
  logic [15:0] g02_q15;
  logic [15:0] g10_q15;
  logic [15:0] g11_q15;
  logic [15:0] g12_q15;
  logic [15:0] g20_q15;
  logic [15:0] g21_q15;
  logic [15:0] g22_q15;
  assign g00_q15 = g2q15(g00);
  assign g01_q15 = g2q15(g01);
  assign g02_q15 = g2q15(g02);
  assign g10_q15 = g2q15(g10);
  assign g11_q15 = g2q15(g11);
  assign g12_q15 = g2q15(g12);
  assign g20_q15 = g2q15(g20);
  assign g21_q15 = g2q15(g21);
  assign g22_q15 = g2q15(g22);

  // Weighted terms: Q1.15 * Q1.15 -> Q1.15 with rounding
  logic [15:0] gw00;
  logic [15:0] gw01;
  logic [15:0] gw02;
  logic [15:0] gw10;
  logic [15:0] gw11;
  logic [15:0] gw12;
  logic [15:0] gw20;
  logic [15:0] gw21;
  logic [15:0] gw22;
  assign gw00 = mul_q15(w00 , g00_q15);
  assign gw01 = mul_q15(w01s, g01_q15);
  assign gw02 = mul_q15(w02 , g02_q15);
  assign gw10 = mul_q15(w10s, g10_q15);
  assign gw11 = mul_q15(w11s, g11_q15);
  assign gw12 = mul_q15(w12s, g12_q15);
  assign gw20 = mul_q15(w20 , g20_q15);
  assign gw21 = mul_q15(w21s, g21_q15);
  assign gw22 = mul_q15(w22 , g22_q15);

  // Wide accumulators to avoid overflow when summing up to 9 terms
  logic [19:0] sum_w_wide;
  logic [19:0] sum_wg_wide;

  always_comb begin
    sum_w_wide  = 20'd0;
    sum_w_wide  = sum_w_wide + w00 + w02 + w20 + w22;
    sum_w_wide  = sum_w_wide + w01s + w10s + w11s + w12s + w21s;

    sum_wg_wide = 20'd0;
    sum_wg_wide = sum_wg_wide + gw00 + gw02 + gw20 + gw22;
    sum_wg_wide = sum_wg_wide + gw01 + gw10 + gw11 + gw12 + gw21;

    S_w  = (sum_w_wide  > 20'd32767) ? 16'd32767 : sum_w_wide[15:0];
    S_wg = (sum_wg_wide > 20'd32767) ? 16'd32767 : sum_wg_wide[15:0];
  end

endmodule
