// top.sv — Fuzzy Logic coprocessor (Sugeno 0-order)

module top (
  input  logic        clk,
  input  logic        rst_n,

  // Simple MMIO bus
  input  logic        cs,
  input  logic        rd,
  input  logic        wr,
  input  logic [7:0]  addr,
  input  logic [7:0]  wdata,
  output logic [7:0]  rdata,

  output logic        status_busy,
  output logic        status_valid
);
  // MMIO wires
  logic       start_pulse, init_pulse;
  logic       reg_mode, dt_mode;
  logic [7:0] T_reg, dT_reg, dT_mon, G_out;
  logic [7:0] T_neg_a, T_neg_b, T_neg_c, T_neg_d;
  logic [7:0] T_zero_a, T_zero_b, T_zero_c, T_zero_d;
  logic [7:0] T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d;
  logic [7:0] dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d;
  logic [7:0] dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d;
  logic [7:0] dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d;
  logic [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;
  logic [7:0] alpha, k_dt, d_max;

  // Status flags
  logic busy_r, valid_r;
  assign status_busy  = busy_r;
  assign status_valid = valid_r;

  // MMIO block
  mmio_if u_mmio_if (
    .clk        (clk),
    .rst_n      (rst_n),
    .cs         (cs),
    .rd         (rd),
    .wr         (wr),
    .addr       (addr),
    .wdata      (wdata),
    .rdata      (rdata),
    .start_pulse(start_pulse),
    .init_pulse (init_pulse),
    .reg_mode   (reg_mode),
    .dt_mode    (dt_mode),
    .T_reg      (T_reg),
    .dT_reg     (dT_reg),
    .dT_mon     (dT_mon),
    .G_out      (G_out),
    .T_neg_a    (T_neg_a), .T_neg_b(T_neg_b), .T_neg_c(T_neg_c), .T_neg_d(T_neg_d),
    .T_zero_a   (T_zero_a),.T_zero_b(T_zero_b),.T_zero_c(T_zero_c),.T_zero_d(T_zero_d),
    .T_pos_a    (T_pos_a), .T_pos_b(T_pos_b), .T_pos_c(T_pos_c), .T_pos_d(T_pos_d),
    .dT_neg_a   (dT_neg_a),.dT_neg_b(dT_neg_b),.dT_neg_c(dT_neg_c),.dT_neg_d(dT_neg_d),
    .dT_zero_a  (dT_zero_a),.dT_zero_b(dT_zero_b),.dT_zero_c(dT_zero_c),.dT_zero_d(dT_zero_d),
    .dT_pos_a   (dT_pos_a), .dT_pos_b(dT_pos_b), .dT_pos_c(dT_pos_c), .dT_pos_d(dT_pos_d),
    .g00        (g00), .g01(g01), .g02(g02),
    .g10        (g10), .g11(g11), .g12(g12),
    .g20        (g20), .g21(g21), .g22(g22),
    .alpha      (alpha),
    .k_dt       (k_dt),
    .d_max      (d_max),
    .busy       (busy_r),
    .valid      (valid_r)
  );

  // Internal dT estimator
  logic [7:0] dT_est;
  logic       dt_valid;
  dt_estimator u_dt_estimator (
    .clk    (clk),
    .rst_n  (rst_n),
    .T_cur  (T_reg),
    .alpha  (alpha),
    .k_dt   (k_dt),
    .d_max  (d_max),
    .init   (init_pulse),
    .dT_out (dT_est),
    .dt_valid(dt_valid)
  );
  assign dT_mon = dT_est;

  // dT source mux
  logic [7:0] dT_sel;
  always_comb begin
    dT_sel = (dt_mode == 1'b1) ? dT_est : dT_reg;
  end

  // Fuzzification
  logic [15:0] muT_neg, muT_zero, muT_pos;
  logic [15:0] muD_neg, muD_zero, muD_pos;

  fuzzifier_T u_fuzz_T (
    .x       (T_reg),
    .a_neg   (T_neg_a),
    .b_neg   (T_neg_b),
    .c_neg   (T_neg_c),
    .d_neg   (T_neg_d),
    .a_zero  (T_zero_a),
    .b_zero  (T_zero_b),
    .c_zero  (T_zero_c),
    .d_zero  (T_zero_d),
    .a_pos   (T_pos_a),
    .b_pos   (T_pos_b),
    .c_pos   (T_pos_c),
    .d_pos   (T_pos_d),
    .mu_neg  (muT_neg),
    .mu_zero (muT_zero),
    .mu_pos  (muT_pos)
  );

  fuzzifier_dT u_fuzz_dT (
    .x       (dT_sel),
    .a_neg   (dT_neg_a),
    .b_neg   (dT_neg_b),
    .c_neg   (dT_neg_c),
    .d_neg   (dT_neg_d),
    .a_zero  (dT_zero_a),
    .b_zero  (dT_zero_b),
    .c_zero  (dT_zero_c),
    .d_zero  (dT_zero_d),
    .a_pos   (dT_pos_a),
    .b_pos   (dT_pos_b),
    .c_pos   (dT_pos_c),
    .d_pos   (dT_pos_d),
    .mu_neg  (muD_neg),
    .mu_zero (muD_zero),
    .mu_pos  (muD_pos)
  );

  // Rules (always compute 9; aggregator gates to 4 if needed)
  logic [15:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
  rules9 u_rules9 (
    .muT_neg (muT_neg),
    .muT_zero(muT_zero),
    .muT_pos (muT_pos),
    .muD_neg (muD_neg),
    .muD_zero(muD_zero),
    .muD_pos (muD_pos),
    .w00     (w00),
    .w01     (w01),
    .w02     (w02),
    .w10     (w10),
    .w11     (w11),
    .w12     (w12),
    .w20     (w20),
    .w21     (w21),
    .w22     (w22)
  );

  // Aggregation and defuzz
  logic [15:0] S_w, S_wg;
  aggregator u_aggregator (
    .reg_mode (reg_mode),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22),
    .g00(g00), .g01(g01), .g02(g02),
    .g10(g10), .g11(g11), .g12(g12),
    .g20(g20), .g21(g21), .g22(g22),
    .S_w      (S_w),
    .S_wg     (S_wg)
  );

  defuzz u_defuzz (
    .clk   (clk),
    .rst_n (rst_n),
    .S_w   (S_w),
    .S_wg  (S_wg),
    .G_out (G_out)
  );

  // Minimal FSM for busy/valid (will be refined if we pipeline)
  typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_e;
  state_e st, st_n;

  always_comb begin
    st_n = st;
    unique case (st)
      S_IDLE: if (start_pulse) st_n = S_RUN;
      S_RUN :                  st_n = S_DONE; // add counters if you pipeline
      S_DONE:                  st_n = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st      <= S_IDLE;
      busy_r  <= 1'b0;
      valid_r <= 1'b0;
    end else begin
      st      <= st_n;
      busy_r  <= (st_n == S_RUN);
      valid_r <= (st_n == S_DONE);
    end
  end
endmodule
