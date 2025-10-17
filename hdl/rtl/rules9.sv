//------------------------------------------------------------------------------
// rules9.sv -- 9 reguł pełnej siatki  (REQ-030/040)
//------------------------------------------------------------------------------
import fuzzy_pkg::*;
module rules9 (
  input  logic [15:0] t_n, t_z, t_p,        // Q1.15
  input  logic [15:0] dt_n, dt_z, dt_p,     // Q1.15
  input  logic [7:0]  g_00, g_01, g_02,
                      g_10, g_11, g_12,
                      g_20, g_21, g_22,     // %
  output logic [23:0] S_w,
  output logic [31:0] S_wg
);
  logic [15:0] w00 = q15_min(t_n, dt_n);
  logic [15:0] w01 = q15_min(t_n, dt_z);
  logic [15:0] w02 = q15_min(t_n, dt_p);
  logic [15:0] w10 = q15_min(t_z, dt_n);
  logic [15:0] w11 = q15_min(t_z, dt_z);
  logic [15:0] w12 = q15_min(t_z, dt_p);
  logic [15:0] w20 = q15_min(t_p, dt_n);
  logic [15:0] w21 = q15_min(t_p, dt_z);
  logic [15:0] w22 = q15_min(t_p, dt_p);

  logic [15:0] g00 = g_percent_to_q15(g_00);
  logic [15:0] g01 = g_percent_to_q15(g_01);
  logic [15:0] g02 = g_percent_to_q15(g_02);
  logic [15:0] g10 = g_percent_to_q15(g_10);
  logic [15:0] g11 = g_percent_to_q15(g_11);
  logic [15:0] g12 = g_percent_to_q15(g_12);
  logic [15:0] g20 = g_percent_to_q15(g_20);
  logic [15:0] g21 = g_percent_to_q15(g_21);
  logic [15:0] g22 = g_percent_to_q15(g_22);

  assign S_w  = w00+w01+w02+w10+w11+w12+w20+w21+w22;

  wire [31:0] s00=w00*g00, s01=w01*g01, s02=w02*g02,
              s10=w10*g10, s11=w11*g11, s12=w12*g12,
              s20=w20*g20, s21=w21*g21, s22=w22*g22;

  assign S_wg = s00+s01+s02+s10+s11+s12+s20+s21+s22;
endmodule
