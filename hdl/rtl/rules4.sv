//------------------------------------------------------------------------------
// rules4.sv -- 4 reguły narożne, wyjścia sum (Σw, Σ(w*g))   (REQ-030/040)
//------------------------------------------------------------------------------
import fuzzy_pkg::*;
module rules4 (
  input  logic [15:0] t_neg, t_pos,     // Q1.15
  input  logic [15:0] dt_neg, dt_pos,   // Q1.15
  input  logic [7:0]  g_00, g_02, g_20, g_22, // %
  output logic [19:0] S_w,              // suma wag
  output logic [31:0] S_wg              // suma wag*gnorm
);
  logic [15:0] w00 = q15_min(t_neg, dt_neg);
  logic [15:0] w02 = q15_min(t_neg, dt_pos);
  logic [15:0] w20 = q15_min(t_pos, dt_neg);
  logic [15:0] w22 = q15_min(t_pos, dt_pos);

  logic [15:0] g00q = g_percent_to_q15(g_00);
  logic [15:0] g02q = g_percent_to_q15(g_02);
  logic [15:0] g20q = g_percent_to_q15(g_20);
  logic [15:0] g22q = g_percent_to_q15(g_22);

  // Σw (szerokość 20 bitów wystarczy)
  assign S_w = w00 + w02 + w20 + w22;

  // Σ(w*g) w Q1.15*Q1.15 => Q2.30 (obcinamy do 32b)
  wire [31:0] w00g = w00 * g00q;
  wire [31:0] w02g = w02 * g02q;
  wire [31:0] w20g = w20 * g20q;
  wire [31:0] w22g = w22 * g22q;

  assign S_wg = w00g + w02g + w20g + w22g;
endmodule
