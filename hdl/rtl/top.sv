// top.sv — koprocesor Fuzzy (Sugeno 0-order)
// REQ: 010,020,030,040,050,060,061,062,110,120,130,210,220,230

module top (
  input  logic        clk,
  input  logic        rst_n,
  // MMIO (prosty synchroniczny)
  input  logic        cs,
  input  logic        rd,
  input  logic        wr,
  input  logic [7:0]  addr,
  input  logic [7:0]  wdata,
  output logic [7:0]  rdata,
  output logic        status_busy,
  output logic        status_valid
);

  // --- rejestry z MMIO ---
  logic        start_pulse, init_pulse;      // REQ-110/062
  logic        reg_mode, dt_mode;            // REQ-030/060
  logic  [7:0] T_reg, dT_reg;                // REQ-010/110

  logic  [7:0] T_neg_a, T_neg_b, T_neg_c, T_neg_d;
  logic  [7:0] T_zero_a, T_zero_b, T_zero_c, T_zero_d;
  logic  [7:0] T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d;

  logic  [7:0] dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d;
  logic  [7:0] dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d;
  logic  [7:0] dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d;

  logic  [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;    // REQ-030
  logic  [7:0] alpha, k_dt, d_max;                     // REQ-061

  logic  [7:0] dT_mon;     // monitor dT z estymatora (REQ-060)
  logic  [7:0] G_out;      // wynik (0..100) (REQ-050)

  // status
  logic busy_r, valid_r;
  assign status_busy  = busy_r;
  assign status_valid = valid_r;

  // --- MMIO ---
  mmio_if u_mmio (
    .clk, .rst_n, .cs, .rd, .wr, .addr, .wdata, .rdata,
    .start_pulse, .init_pulse, .reg_mode, .dt_mode,
    .T_reg, .dT_reg, .dT_mon, .G_out,
    .T_neg_a, .T_neg_b, .T_neg_c, .T_neg_d,
    .T_zero_a, .T_zero_b, .T_zero_c, .T_zero_d,
    .T_pos_a, .T_pos_b, .T_pos_c, .T_pos_d,
    .dT_neg_a, .dT_neg_b, .dT_neg_c, .dT_neg_d,
    .dT_zero_a, .dT_zero_b, .dT_zero_c, .dT_zero_d,
    .dT_pos_a, .dT_pos_b, .dT_pos_c, .dT_pos_d,
    .g00,.g01,.g02,.g10,.g11,.g12,.g20,.g21,.g22,
    .alpha,.k_dt,.d_max,
    .busy(busy_r), .valid(valid_r)
  );

  // --- dT estimator (REQ-060) ---
  logic [7:0] dT_est; logic dt_valid;
  dt_estimator u_dt (
    .clk, .rst_n, .T_cur(T_reg), .alpha, .k_dt, .d_max,
    .init(init_pulse), .dT_out(dT_est), .dt_valid
  );
  assign dT_mon = dT_est;
  logic [7:0] dT_sel = dt_mode ? dT_est : dT_reg;

  // --- fuzzification (REQ-020) ---
  logic [15:0] muT_neg, muT_zero, muT_pos;
  logic [15:0] muD_neg, muD_zero, muD_pos;

  fuzzifier_T  u_fT  (.*,
    .x(T_reg),
    .a_neg(T_neg_a), .b_neg(T_neg_b), .c_neg(T_neg_c), .d_neg(T_neg_d),
    .a_zero(T_zero_a), .b_zero(T_zero_b), .c_zero(T_zero_c), .d_zero(T_zero_d),
    .a_pos(T_pos_a), .b_pos(T_pos_b), .c_pos(T_pos_c), .d_pos(T_pos_d),
    .mu_neg(muT_neg), .mu_zero(muT_zero), .mu_pos(muT_pos));

  fuzzifier_dT u_fdT (.*,
    .x(dT_sel),
    .a_neg(dT_neg_a), .b_neg(dT_neg_b), .c_neg(dT_neg_c), .d_neg(dT_neg_d),
    .a_zero(dT_zero_a), .b_zero(dT_zero_b), .c_zero(dT_zero_c), .d_zero(dT_zero_d),
    .a_pos(dT_pos_a), .b_pos(dT_pos_b), .c_pos(dT_pos_c), .d_pos(dT_pos_d),
    .mu_neg(muD_neg), .mu_zero(muD_zero), .mu_pos(muD_pos));

  // --- rules + aggregator (REQ-030/040) ---
  logic [15:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
  rules9 u_r9 (.*,
    .muT_neg, .muT_zero, .muT_pos,
    .muD_neg, .muD_zero, .muD_pos,
    .w00,.w01,.w02,.w10,.w11,.w12,.w20,.w21,.w22);

  logic [15:0] S_w, S_wg;
  aggregator u_aggr (.*,
    .reg_mode, .w00,.w01,.w02,.w10,.w11,.w12,.w20,.w21,.w22,
    .g00,.g01,.g02,.g10,.g11,.g12,.g20,.g21,.g22, .S_w, .S_wg);

  defuzz u_defuzz  (.*,.S_w(S_w), .S_wg(S_wg), .G_out(G_out));

  // --- prosty FSM (REQ-230) ---
  typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_e;
  state_e st, st_n;

  always_comb begin
    st_n = st;
    unique case (st)
      S_IDLE: if (start_pulse) st_n = S_RUN;
      S_RUN : st_n = S_DONE;   // TODO: zarejestruj etapy jeśli potrzeba timing
      S_DONE: st_n = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      st <= S_IDLE; busy_r <= 1'b0; valid_r <= 1'b0;
    end else begin
      st <= st_n;
      busy_r  <= (st_n == S_RUN);
      valid_r <= (st_n == S_DONE);
    end
  end

endmodule
