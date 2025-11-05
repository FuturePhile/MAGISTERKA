// top_coprocessor.v - Fuzzy Logic coprocessor core (direct I/O, no bus)
// Wersja: DONE po 8 cyklach od START, + wyjścia diagnostyczne.

module top_coprocessor (
  input         clk,
  input         rst_n,
  input         start,           // level; rising edge starts evaluation
  input         init,            // level; rising edge re-inits dT estimator
  input         reg_mode,        // 0: 4 rules, 1: 9 rules
  input         dt_mode,         // 0: external dT_in, 1: internal estimator
  input  signed [7:0] T_in,      // Q7.0
  input  signed [7:0] dT_in,     // ignored when dt_mode=1
  input  signed [7:0] T_neg_a,
  input  signed [7:0] T_neg_b,
  input  signed [7:0] T_neg_c,
  input  signed [7:0] T_neg_d,
  input  signed [7:0] T_zero_a,
  input  signed [7:0] T_zero_b,
  input  signed [7:0] T_zero_c,
  input  signed [7:0] T_zero_d,
  input  signed [7:0] T_pos_a,
  input  signed [7:0] T_pos_b,
  input  signed [7:0] T_pos_c,
  input  signed [7:0] T_pos_d,
  input  signed [7:0] dT_neg_a,
  input  signed [7:0] dT_neg_b,
  input  signed [7:0] dT_neg_c,
  input  signed [7:0] dT_neg_d,
  input  signed [7:0] dT_zero_a,
  input  signed [7:0] dT_zero_b,
  input  signed [7:0] dT_zero_c,
  input  signed [7:0] dT_zero_d,
  input  signed [7:0] dT_pos_a,
  input  signed [7:0] dT_pos_b,
  input  signed [7:0] dT_pos_c,
  input  signed [7:0] dT_pos_d,
  output reg        valid,           // 1-cycle DONE pulse (po 8 cyklach)
  output reg  [7:0] G_out,           // 0..100 wynik (rejestrowany)

  // ===== DEBUG (do mmio_if RO) =====
  output      [15:0] dbg_S_w,
  output      [15:0] dbg_S_wg,
  output      [7:0]  dbg_G_q,
  output signed[7:0] dbg_dT_sel
);

  // Singletony i stałe
  localparam [7:0] G00 = 8'd100, G01 = 8'd50,  G02 = 8'd30;
  localparam [7:0] G10 = 8'd50,  G11 = 8'd50,  G12 = 8'd50;
  localparam [7:0] G20 = 8'd80,  G21 = 8'd50,  G22 = 8'd0;
  localparam [7:0] ALPHA_P = 8'd32;  // ≈ alpha/256
  localparam [7:0] KDT_P   = 8'd3;   // divide by 2^k
  localparam [7:0] DMAX_P  = 8'd64;  // clamp Q7.0

  // Edge detect dla start/init
  reg  start_q, init_q;
  wire start_pulse = start & ~start_q;
  wire init_pulse  = init  & ~init_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_q <= 1'b0; init_q <= 1'b0;
    end else begin
      start_q <= start; init_q <= init;
    end
  end

  // Estymator dT
  wire signed [7:0] dT_est;  wire dt_valid;
  dt_estimator u_dt_estimator (
    .clk(clk), .rst_n(rst_n), .T_cur(T_in),
    .alpha(ALPHA_P), .k_dt(KDT_P), .d_max(DMAX_P),
    .init(init_pulse),
    .dT_out(dT_est), .dt_valid(dt_valid)
  );

  // dT select
  wire signed [7:0] dT_sel = dt_mode ? dT_est : dT_in;
  assign dbg_dT_sel = dT_sel;

  // Fuzzification T
  wire [15:0] muT_neg, muT_zero, muT_pos;
  fuzzifier_T u_fuzz_T (
    .x(T_in),
    .a_neg(T_neg_a), .b_neg(T_neg_b), .c_neg(T_neg_c), .d_neg(T_neg_d),
    .a_zero(T_zero_a), .b_zero(T_zero_b), .c_zero(T_zero_c), .d_zero(T_zero_d),
    .a_pos(T_pos_a), .b_pos(T_pos_b), .c_pos(T_pos_c), .d_pos(T_pos_d),
    .mu_neg(muT_neg), .mu_zero(muT_zero), .mu_pos(muT_pos)
  );

  // Fuzzification dT
  wire [15:0] muD_neg, muD_zero, muD_pos;
  fuzzifier_dT u_fuzz_dT (
    .x(dT_sel),
    .a_neg(dT_neg_a), .b_neg(dT_neg_b), .c_neg(dT_neg_c), .d_neg(dT_neg_d),
    .a_zero(dT_zero_a), .b_zero(dT_zero_b), .c_zero(dT_zero_c), .d_zero(dT_zero_d),
    .a_pos(dT_pos_a), .b_pos(dT_pos_b), .c_pos(dT_pos_c), .d_pos(dT_pos_d),
    .mu_neg(muD_neg), .mu_zero(muD_zero), .mu_pos(muD_pos)
  );

  // Rules 9
  wire [15:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
  rules9 u_rules9 (
    .muT_neg(muT_neg), .muT_zero(muT_zero), .muT_pos(muT_pos),
    .muD_neg(muD_neg), .muD_zero(muD_zero), .muD_pos(muD_pos),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22)
  );

  // Agregacja
  wire [15:0] S_w, S_wg;
  aggregator u_aggregator (
    .reg_mode(reg_mode),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22),
    .g00(G00), .g01(G01), .g02(G02),
    .g10(G10), .g11(G11), .g12(G12),
    .g20(G20), .g21(G21), .g22(G22),
    .S_w(S_w), .S_wg(S_wg)
  );
  assign dbg_S_w  = S_w;
  assign dbg_S_wg = S_wg;

  // Defuzyfikacja (rejestrowany wynik)
  wire [7:0] G_q;
  defuzz u_defuzz (
    .clk(clk), .rst_n(rst_n),
    .S_w(S_w), .S_wg(S_wg),
    .G_out(G_q)
  );
  assign dbg_G_q = G_q;

  // --- Licznik opóźniający DONE o N cykli ---
  localparam integer DONE_LAT = 8;
  reg [$clog2(DONE_LAT+1)-1:0] cnt;
  reg running;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      running <= 1'b0;
      cnt     <= {($clog2(DONE_LAT+1)){1'b0}};
      valid   <= 1'b0;
      G_out   <= 8'd0;
    end else begin
      valid <= 1'b0;                 // domyślnie brak DONE

      if (start_pulse && !running) begin
        running <= 1'b1;
        cnt     <= DONE_LAT[$clog2(DONE_LAT+1)-1:0];
      end else if (running) begin
        if (cnt != 0) begin
          cnt <= cnt - 1'b1;
        end else begin
          running <= 1'b0;
          valid   <= 1'b1;           // DONE 1 takt
        end
      end

      // Próbkuj wynik w każdym cyklu (weźmiesz najnowszy)
      G_out <= G_q;
    end
  end

endmodule
