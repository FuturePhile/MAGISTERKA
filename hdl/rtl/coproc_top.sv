//------------------------------------------------------------------------------
// coproc_top.sv -- TOP koprocesora (REQ-010..050, 060..062, 110..130, 230)
//------------------------------------------------------------------------------
import fuzzy_pkg::*;
module coproc_top (
  input  logic        clk,
  input  logic        rst,
  // MMIO
  input  logic        cs, wr, rd,
  input  logic [7:0]  addr,
  input  logic [7:0]  wdata,
  output logic [7:0]  rdata
);
  // Sygnały rejestrowe
  logic start, reg_mode, dt_mode, init;
  logic signed [7:0] T_reg, dT_reg;
  logic signed [7:0] dT_est;
  logic        busy, valid;
  logic [7:0]  G_out;

  // MF params + g + estymator
  logic signed [7:0] Tn_a,Tn_b,Tn_c,Tn_d, Tz_a,Tz_b,Tz_c,Tz_d, Tp_a,Tp_b,Tp_c,Tp_d;
  logic signed [7:0] dTn_a,dTn_b,dTn_c,dTn_d, dTz_a,dTz_b,dTz_c,dTz_d, dTp_a,dTp_b,dTp_c,dTp_d;
  logic [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;
  logic [7:0] ALPHA, K_DT; logic signed [7:0] D_MAX;

  mmio_if u_mmio (
    .clk, .rst,
    .cs, .wr, .rd, .addr, .wdata, .rdata,
    .start_pulse(start), .reg_mode(reg_mode), .dt_mode(dt_mode), .init_pulse(init),
    .T_reg, .dT_reg,
    .Tn_a, .Tn_b, .Tn_c, .Tn_d,
    .Tz_a, .Tz_b, .Tz_c, .Tz_d,
    .Tp_a, .Tp_b, .Tp_c, .Tp_d,
    .dTn_a, .dTn_b, .dTn_c, .dTn_d,
    .dTz_a, .dTz_b, .dTz_c, .dTz_d,
    .dTp_a, .dTp_b, .dTp_c, .dTp_d,
    .g_00(g00), .g_01(g01), .g_02(g02),
    .g_10(g10), .g_11(g11), .g_12(g12),
    .g_20(g20), .g_21(g21), .g_22(g22),
    .ALPHA, .K_DT, .D_MAX,
    .busy, .valid, .dT_live(dT_est), .G_out
  );

  // Estymator dT (aktywny, nawet gdy dt_mode=0 wystawiamy do STATUS/odczytu)
  dt_estimator u_dt (
    .clk, .rst, .init(init),
    .T_in(T_reg), .ALPHA, .K_DT, .D_MAX,
    .dT_out(dT_est)
  );

  // FUZZY pipeline
  // C1: fuzzification
  logic [15:0] t_n,t_z,t_p, dt_n,dt_z,dt_p;
  wire  signed [7:0] dT_mux = (dt_mode) ? dT_est : dT_reg;

  fuzzifier u_fz_T  (.clk, .x(T_reg),
    .n_a(Tn_a), .n_b(Tn_b), .n_c(Tn_c), .n_d(Tn_d),
    .z_a(Tz_a), .z_b(Tz_b), .z_c(Tz_c), .z_d(Tz_d),
    .p_a(Tp_a), .p_b(Tp_b), .p_c(Tp_c), .p_d(Tp_d),
    .mu_neg(t_n), .mu_zero(t_z), .mu_pos(t_p));

  fuzzifier u_fz_dT (.clk, .x(dT_mux),
    .n_a(dTn_a), .n_b(dTn_b), .n_c(dTn_c), .n_d(dTn_d),
    .z_a(dTz_a), .z_b(dTz_b), .z_c(dTz_c), .z_d(dTz_d),
    .p_a(dTp_a), .p_b(dTp_b), .p_c(dTp_c), .p_d(dTp_d),
    .mu_neg(dt_n), .mu_zero(dt_z), .mu_pos(dt_p));

  // C2: reguły + agregacja
  logic [23:0] S_w;
  logic [31:0] S_wg;
  always_comb begin
    if (reg_mode==1'b0) begin
      rules4 r4(
        .t_neg(t_n), .t_pos(t_p),
        .dt_neg(dt_n), .dt_pos(dt_p),
        .g_00(g00), .g_02(g02), .g_20(g20), .g_22(g22),
        .S_w(S_w[19:0]), .S_wg(S_wg) // niższe bity, reszta 0
      );
    end else begin
      rules9 r9(
        .t_n(t_n), .t_z(t_z), .t_p(t_p),
        .dt_n(dt_n), .dt_z(dt_z), .dt_p(dt_p),
        .g_00(g00), .g_01(g01), .g_02(g02),
        .g_10(g10), .g_11(g11), .g_12(g12),
        .g_20(g20), .g_21(g21), .g_22(g22),
        .S_w(S_w), .S_wg(S_wg)
      );
    end
  end

  // C3: defuzz
  defuzz u_def (.clk, .start(start), .S_w(S_w), .S_wg(S_wg), .valid(valid), .G_percent(G_out));

  // busy: od start do valid
  typedef enum logic [1:0] {IDLE, RUN} st_t;
  st_t st;
  always_ff @(posedge clk) begin
    if (rst) begin
      st <= IDLE; busy <= 1'b0;
    end else begin
      case (st)
        IDLE: begin
          busy <= 1'b0;
          if (start) begin st <= RUN; busy <= 1'b1; end
        end
        RUN: begin
          if (valid) begin st <= IDLE; busy <= 1'b0; end
        end
      endcase
    end
  end

endmodule
