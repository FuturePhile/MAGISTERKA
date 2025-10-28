// tb_dt_estimator_req060.sv — unit TB for dt_estimator
// Covers: REQ-060 (internal dT estimation), REQ-061 (alpha/k/d_max effects),
//         REQ-062 (INIT reset w/o spike), REQ-210 (fixed-point ranges)

`timescale 1ns/1ps
module tb_dt_estimator_req060;
  timeunit 1ns; timeprecision 1ps;

  // === Clock & reset ===
  logic clk; logic rst_n; localparam real TCLK_NS = 10.0;
  initial begin clk = 1'b0; forever #(TCLK_NS/2.0) clk = ~clk; end

  // === DUT ports ===
  logic              init;
  logic signed [7:0] T_cur;
  logic       [7:0]  alpha;    // ~ alpha/256
  logic       [7:0]  k_dt;     // /2^k
  logic       [7:0]  d_max;    // |dT| clamp (Q7.0)
  logic signed [7:0] dT_out;   // Q7.0
  logic              dt_valid;

  int i;
  int j;
  int step, nxt;

  logic [3:0] k_div_lim;

  // === Instantiate DUT ===
  dt_estimator dut (
    .clk(clk),
    .rst_n(rst_n),
    .T_cur(T_cur),
    .alpha(alpha),
    .k_dt(k_dt),
    .d_max(d_max),
    .init(init),
    .dT_out(dT_out),
    .dt_valid(dt_valid)
  );

  // === Bit-accurate reference (mirrors RTL math) ===
  logic signed [7:0]  ref_T_prev;
  logic signed [15:0] ref_dT_prev_q15;   // Q0.7

  function automatic signed [15:0] to_q15_from_s8 (input logic signed [7:0] x_s8);
    to_q15_from_s8 = {x_s8, 7'b0};
  endfunction

  function automatic logic signed [7:0] ref_step_expect (
    input logic signed [7:0]  T_now,
    input logic        [7:0]  alpha_u8,
    input logic        [7:0]  k_div,
    input logic        [7:0]  dmax_s8,
    input bit                do_init,
    input bit                do_reset
  );
    logic signed [8:0]  delta_q8;         // Q8.0
    logic signed [15:0] delta_q07;        // Q0.7
    logic signed [15:0] delta_scaled;     // Q0.7
    logic       [15:0]  inv_a_u, a_u;     // 0..256
    logic signed [31:0] term1, term2, sum32;
    logic signed [15:0] dT_new_q15;       // Q0.7
    logic signed [15:0] dmax_q15, clip_hi, clip_lo;
    logic signed [15:0] q07_adj;

    if (do_reset) begin
      ref_T_prev       = '0;
      ref_dT_prev_q15  = '0;
      return 8'sd0;
    end

    if (do_init) begin
      ref_T_prev       = T_now;  // jak DUT
      ref_dT_prev_q15  = '0;     // wyzeruj EMA
      return 8'sd0;              // na cyklu INIT wyjście 0
    end

    delta_q8     = $signed({{1{T_now[7]}}, T_now}) - $signed({{1{ref_T_prev[7]}}, ref_T_prev});
    delta_q07    = $signed(delta_q8) <<< 7;

    k_div_lim = (k_div > 8'd7) ? 4'd7 : k_div[3:0];
    delta_scaled = delta_q07 >>> k_div_lim;

    inv_a_u      = 16'd256 - {8'b0, alpha_u8};
    a_u          = {8'b0, alpha_u8};

    term1        = $signed(ref_dT_prev_q15) * $signed(inv_a_u);
    term2        = $signed(delta_scaled)    * $signed(a_u);
    sum32        = term1 + term2;
    dT_new_q15   = $signed(sum32 >>> 8);

    dmax_q15     = $signed(dmax_s8) <<< 7;
    clip_hi      = (dT_new_q15 >  dmax_q15) ?  dmax_q15 : dT_new_q15;
    clip_lo      = (clip_hi    < -dmax_q15) ? -dmax_q15 : clip_hi;

    ref_T_prev       = T_now;
    ref_dT_prev_q15  = clip_lo;

    q07_adj          = (clip_lo < 0) ? (clip_lo + 16'sd127) : clip_lo;
    return $signed(q07_adj >>> 7);
  endfunction

  // === Helpers ===
  task automatic apply_reset();
    rst_n = 1'b0; init = 1'b0; T_cur = '0; alpha = 8'd32; k_dt = 8'd3; d_max = 8'd64;
    repeat (3) @(posedge clk);
    rst_n = 1'b1; @(posedge clk); #1step; // poczekaj na NBA
    void'(ref_step_expect(0, alpha, k_dt, d_max, /*init*/0, /*reset*/1));
  endtask

  // nieużywane, zostawione dla kompletności
  task automatic pulse_init();
    @(negedge clk); init <= 1'b1;
    @(posedge clk); #1step init <= 1'b0;
  endtask

  task automatic step_and_check(
    input string tag,
    input logic signed [7:0] T_next,
    input bit expect_valid
  );
    logic signed [7:0] exp_dT;
    // wystaw dane przed posedge
    @(negedge clk); T_cur = T_next;
    // policz oczekiwane na nadchodzący posedge
    exp_dT = ref_step_expect(T_next, alpha, k_dt, d_max, /*init*/0, /*reset*/0);
    // posedge DUT -> NBA update -> #1step: próbkuj po NBA
    @(posedge clk); #1step;
    assert (dt_valid == expect_valid)
      else $error("[REQ-060] %s dt_valid mismatch: got=%0b exp=%0b", tag, dt_valid, expect_valid);
    assert (dT_out == exp_dT)
      else $error("[REQ-060] %s dT_out mismatch: got=%0d exp=%0d", tag, $signed(dT_out), $signed(exp_dT));
    assert (($signed(dT_out) <= $signed(d_max)) && ($signed(dT_out) >= -$signed(d_max)))
      else $error("[REQ-061] %s clamp violated: dT_out=%0d d_max=%0d", tag, $signed(dT_out), $signed(d_max));
    $display("INFO: [EST] %s | T=%0d -> dT=%0d (valid=%0b)", tag, $signed(T_next), $signed(dT_out), dt_valid);
  endtask

  // === INIT bez race + sampling po NBA ===
  task automatic do_init_and_check(string tag);
    // 1) Krok przed INIT
    step_and_check({tag," pre"}, 8'sd5, /*expect_valid*/1);

    // 2) Zgłoś INIT tak, by DUT zobaczył go na posedge
    @(negedge clk); init <= 1'b1;

    // 3) Posedge INIT: DUT nadaje 0/0; poczekaj na NBA i sprawdź
    @(posedge clk); #1step;

    // zsynchronizuj referencję do cyklu INIT
    void'(ref_step_expect(T_cur, alpha, k_dt, d_max, /*do_init*/1, /*do_reset*/0));

    assert (dt_valid == 1'b0) else $error("[REQ-062] %s dt_valid must be 0 on INIT cycle", tag);
    assert (dT_out  == 8'sd0) else $error("[REQ-062] %s dT_out must be 0 on INIT cycle", tag);
    $display("INFO: [EST] %s after INIT | dT=%0d valid=%0b", tag, $signed(dT_out), dt_valid);

    // 4) zdejmij INIT po posedge, po NBA
    #1step init <= 1'b0;

    // 5) Następny krok po INIT (valid=1)
    step_and_check({tag," post"}, T_cur, /*expect_valid*/1);
  endtask

  // === Test plan ===
  initial begin
    alpha = 8'd32;   // ~ 32/256
    k_dt  = 8'd3;    // /8
    d_max = 8'd64;   // |dT|<=64
    T_cur = 8'sd0; init = 1'b0;

    // A) Reset & INIT
    apply_reset();
    step_and_check("A1 after reset (first)", 8'sd0, /*expect_valid*/1);
    do_init_and_check("A2 INIT");

    // B) Sign & scale
    @(negedge clk); T_cur = 8'sd0; void'(ref_step_expect(T_cur, alpha, k_dt, d_max, 0, 0)); @(posedge clk); #1step;
    step_and_check("B1 +step T:0→40", 8'sd40, 1);
    step_and_check("B2 -step T:40→-40", -8'sd40, 1);

    k_dt = 8'd6;
    step_and_check("B3 k_dt=6 small response (hold T)", T_cur, 1);
    step_and_check("B4 k_dt=6 +step T:-40→+40", 8'sd40, 1);

    k_dt = 8'd3;
    step_and_check("B5 k_dt=3 settle (hold T)", T_cur, 1);

    // C) Alpha effect
    alpha = 8'd8;
    do_init_and_check("C1 alpha=8 reinit");
    step_and_check("C2 alpha=8 +step 0→40", 8'sd40, 1);

    alpha = 8'd128;
    do_init_and_check("C3 alpha=128 reinit");
    step_and_check("C4 alpha=128 +step 0→40", 8'sd40, 1);

    // D) Clamp
    alpha = 8'd255; k_dt  = 8'd0; d_max = 8'd10;
    do_init_and_check("D1 clamp reinit");
    step_and_check("D2 clamp +", 8'sd127, 1);
    step_and_check("D3 clamp -", -8'sd128, 1);

    // E) Sweep / random walk
    alpha = 8'd32; k_dt = 8'd3; d_max = 8'd64;
    do_init_and_check("E0 reinit nominal");

    for (i=0; i<=10; i++) step_and_check($sformatf("E1 ramp↑ i=%0d", i), i*3, 1);
    for (i=10; i>=0; i--) step_and_check($sformatf("E2 ramp↓ i=%0d", i), i*3, 1);

    for (j=0; j<50; j++) begin
      step = $urandom_range(-7,7);
      nxt  = $signed(T_cur) + step;
      if (nxt > 127) nxt = 127; if (nxt < -128) nxt = -128;
      step_and_check($sformatf("E3 rnd j=%0d", j), nxt[7:0], 1);
      assert (($signed(dT_out) >= -$signed(d_max)) && ($signed(dT_out) <= $signed(d_max)))
        else $error("[REQ-210] E3 bound violated");
    end

    $display("[REQ-060][REQ-061][REQ-062][REQ-210] dt_estimator TB finished");
    $finish;
  end
endmodule
