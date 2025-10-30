// top_coprocessor.sv - Fuzzy Logic coprocessor core (direct I/O, no bus)
// External visibility: only VALID and G_out are read by MCU (via mmio_if).
// All other signals are direct inputs from the shadow registers.
module top_coprocessor (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,           // level; rising edge starts evaluation
  input  logic        init,            // level; rising edge re-inits dT estimator
  input  logic        reg_mode,        // 0: 4 rules, 1: 9 rules
  input  logic        dt_mode,         // 0: external dT_in, 1: internal estimator
  input  logic signed [7:0] T_in,      // Q7.0
  input  logic signed [7:0] dT_in,     // ignored when dt_mode=1
  input  logic signed [7:0] T_neg_a,
  input  logic signed [7:0] T_neg_b,
  input  logic signed [7:0] T_neg_c,
  input  logic signed [7:0] T_neg_d,
  input  logic signed [7:0] T_zero_a,
  input  logic signed [7:0] T_zero_b,
  input  logic signed [7:0] T_zero_c,
  input  logic signed [7:0] T_zero_d,
  input  logic signed [7:0] T_pos_a,
  input  logic signed [7:0] T_pos_b,
  input  logic signed [7:0] T_pos_c,
  input  logic signed [7:0] T_pos_d,
  input  logic signed [7:0] dT_neg_a,
  input  logic signed [7:0] dT_neg_b,
  input  logic signed [7:0] dT_neg_c,
  input  logic signed [7:0] dT_neg_d,
  input  logic signed [7:0] dT_zero_a,
  input  logic signed [7:0] dT_zero_b,
  input  logic signed [7:0] dT_zero_c,
  input  logic signed [7:0] dT_zero_d,
  input  logic signed [7:0] dT_pos_a,
  input  logic signed [7:0] dT_pos_b,
  input  logic signed [7:0] dT_pos_c,
  input  logic signed [7:0] dT_pos_d,
  output logic        valid,           // 1-cycle DONE pulse
  output logic  [7:0] G_out            // 0..100 result (registered)
);

  // Singletons and estimator params (constants fixed in RTL)
  localparam logic [7:0] G00 = 8'd100;
  localparam logic [7:0] G01 = 8'd50;
  localparam logic [7:0] G02 = 8'd30;
  localparam logic [7:0] G10 = 8'd50;
  localparam logic [7:0] G11 = 8'd50;
  localparam logic [7:0] G12 = 8'd50;
  localparam logic [7:0] G20 = 8'd80;
  localparam logic [7:0] G21 = 8'd50;
  localparam logic [7:0] G22 = 8'd0;
  localparam logic [7:0] ALPHA_P = 8'd32;  // approx alpha/256
  localparam logic [7:0] KDT_P   = 8'd3;   // divide by 2^k
  localparam logic [7:0] DMAX_P  = 8'd64;  // clamp Q7.0

  // Edge detect for start/init
  logic start_q;
  logic init_q;
  logic start_pulse;
  logic init_pulse;
  assign start_pulse = start & ~start_q;
  assign init_pulse  = init  & ~init_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_q <= 1'b0;
      init_q  <= 1'b0;
    end else begin
      start_q <= start;
      init_q  <= init;
    end
  end

  // Internal dT estimator
  logic signed [7:0] dT_est;
  logic              dt_valid;
  dt_estimator u_dt_estimator (
    .clk(clk),
    .rst_n(rst_n),
    .T_cur(T_in),
    .alpha(ALPHA_P),
    .k_dt(KDT_P),
    .d_max(DMAX_P),
    .init(init_pulse),
    .dT_out(dT_est),
    .dt_valid(dt_valid)
  );

  // dT select
  logic signed [7:0] dT_sel;
  assign dT_sel = dt_mode ? dT_est : dT_in;

  // Fuzzification for T
  logic [15:0] muT_neg;
  logic [15:0] muT_zero;
  logic [15:0] muT_pos;
  fuzzifier_T u_fuzz_T (
    .x(T_in),
    .a_neg(T_neg_a),
    .b_neg(T_neg_b),
    .c_neg(T_neg_c),
    .d_neg(T_neg_d),
    .a_zero(T_zero_a),
    .b_zero(T_zero_b),
    .c_zero(T_zero_c),
    .d_zero(T_zero_d),
    .a_pos(T_pos_a),
    .b_pos(T_pos_b),
    .c_pos(T_pos_c),
    .d_pos(T_pos_d),
    .mu_neg(muT_neg),
    .mu_zero(muT_zero),
    .mu_pos(muT_pos)
  );

  // Fuzzification for dT
  logic [15:0] muD_neg;
  logic [15:0] muD_zero;
  logic [15:0] muD_pos;
  fuzzifier_dT u_fuzz_dT (
    .x(dT_sel),
    .a_neg(dT_neg_a),
    .b_neg(dT_neg_b),
    .c_neg(dT_neg_c),
    .d_neg(dT_neg_d),
    .a_zero(dT_zero_a),
    .b_zero(dT_zero_b),
    .c_zero(dT_zero_c),
    .d_zero(dT_zero_d),
    .a_pos(dT_pos_a),
    .b_pos(dT_pos_b),
    .c_pos(dT_pos_c),
    .d_pos(dT_pos_d),
    .mu_neg(muD_neg),
    .mu_zero(muD_zero),
    .mu_pos(muD_pos)
  );

  // Rules
  logic [15:0] w00;
  logic [15:0] w01;
  logic [15:0] w02;
  logic [15:0] w10;
  logic [15:0] w11;
  logic [15:0] w12;
  logic [15:0] w20;
  logic [15:0] w21;
  logic [15:0] w22;
  rules9 u_rules9 (
    .muT_neg(muT_neg),
    .muT_zero(muT_zero),
    .muT_pos(muT_pos),
    .muD_neg(muD_neg),
    .muD_zero(muD_zero),
    .muD_pos(muD_pos),
    .w00(w00),
    .w01(w01),
    .w02(w02),
    .w10(w10),
    .w11(w11),
    .w12(w12),
    .w20(w20),
    .w21(w21),
    .w22(w22)
  );

  // Aggregation
  logic [15:0] S_w;
  logic [15:0] S_wg;
  aggregator u_aggregator (
    .reg_mode(reg_mode),
    .w00(w00),
    .w01(w01),
    .w02(w02),
    .w10(w10),
    .w11(w11),
    .w12(w12),
    .w20(w20),
    .w21(w21),
    .w22(w22),
    .g00(G00),
    .g01(G01),
    .g02(G02),
    .g10(G10),
    .g11(G11),
    .g12(G12),
    .g20(G20),
    .g21(G21),
    .g22(G22),
    .S_w(S_w),
    .S_wg(S_wg)
  );

  // Defuzz
  logic [7:0] G_q;
  defuzz u_defuzz (
    .clk(clk),
    .rst_n(rst_n),
    .S_w(S_w),
    .S_wg(S_wg),
    .G_out(G_q)
  );

  // Tiny FSM: one-cycle latency -> VALID on next cycle
  typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_e;
  state_e st;
  state_e st_n;

  always_comb begin
    st_n = st;
    unique case (st)
      S_IDLE: if (start_pulse) st_n = S_RUN;
      S_RUN : st_n = S_DONE;
      S_DONE: st_n = S_IDLE;
      default: st_n = S_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st    <= S_IDLE;
      valid <= 1'b0;
      G_out <= 8'd0;
    end else begin
      st    <= st_n;
      valid <= (st_n == S_DONE);
      G_out <= G_q;
    end
  end

endmodule
