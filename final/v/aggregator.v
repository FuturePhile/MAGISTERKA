// aggregator.v — sumowanie wag i wag*G (bez „magii” skalowania)
// Wejścia w_ij: Q1.15 (0..0x7FFF), g_ij: bajt 0..100
// Wyjścia S_w, S_wg: Q1.15 (0..0x7FFF) — spójne skale dla defuzz

module aggregator (
  input        reg_mode,        // 1: 9 reguł, 0: 4 reguły (krzyż)
  input  [15:0] w00, input [15:0] w01, input [15:0] w02,
  input  [15:0] w10, input [15:0] w11, input [15:0] w12,
  input  [15:0] w20, input [15:0] w21, input [15:0] w22,
  input  [7:0]  g00, input [7:0]  g01, input [7:0]  g02,
  input  [7:0]  g10, input [7:0]  g11, input [7:0]  g12,
  input  [7:0]  g20, input [7:0]  g21, input [7:0]  g22,
  output [15:0] S_w,             // Q1.15
  output [15:0] S_wg             // Q1.15
);

  // wybór reguł według trybu
  wire use9 = reg_mode;

  // ——— suma wag ———
  wire [18:0] sum_w_9 =
      w00 + w01 + w02 +
      w10 + w11 + w12 +
      w20 + w21 + w22;

  // 4-regułowy „krzyż”: środek + osie (dostosuj jeśli chcesz inny zestaw)
  wire [18:0] sum_w_4 =
      w01 + w10 + w11 + w12 + w21;

  wire [18:0] sum_w_sel = use9 ? sum_w_9 : sum_w_4;

  // clamp do Q1.15
  assign S_w = (sum_w_sel[18:15] != 0) ? 16'h7FFF : sum_w_sel[15:0];

  // ——— suma w*g/100 ———
  // używamy szerokiej akumulacji, żeby nie gubić precyzji
  function [31:0] mul_wg_div100;
    input [15:0] w;
    input [7:0]  g;   // 0..100
    reg   [23:0] prod; // 16*8=24 bit
  begin
    prod = w * g;                 // max ≈ 0x7FFF * 100 ≈ 0x30D3C3
    // dzielenie przez 100: aproksymacja dokładna dzieleniem (Vivado zrobi DSP/shift+add)
    mul_wg_div100 = prod / 8'd100;
  end
  endfunction

  wire [31:0] sum_wg_9 =
      mul_wg_div100(w00,g00) + mul_wg_div100(w01,g01) + mul_wg_div100(w02,g02) +
      mul_wg_div100(w10,g10) + mul_wg_div100(w11,g11) + mul_wg_div100(w12,g12) +
      mul_wg_div100(w20,g20) + mul_wg_div100(w21,g21) + mul_wg_div100(w22,g22);

  wire [31:0] sum_wg_4 =
      mul_wg_div100(w01,g01) +  // T=neg, dT=zero
      mul_wg_div100(w10,g10) +  // T=zero, dT=neg
      mul_wg_div100(w11,g11) +  // środek
      mul_wg_div100(w12,g12) +  // T=zero, dT=pos
      mul_wg_div100(w21,g21);   // T=pos,  dT=zero

  wire [31:0] sum_wg_sel = use9 ? sum_wg_9 : sum_wg_4;

  // clamp do 0x7FFF (Q1.15)
  assign S_wg = (sum_wg_sel[31:15] != 0) ? 16'h7FFF : sum_wg_sel[15:0];

endmodule
