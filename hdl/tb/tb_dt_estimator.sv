`timescale 1ns/1ps

module tb_dt_estimator;
  // Clock/reset
  logic clk=0, rst_n=0;
  always #5 clk = ~clk;

  // DUT I/O
  logic  signed [7:0] T_cur;
  logic        [7:0] alpha, k_dt, d_max;
  logic              init;
  logic  signed [7:0] dT_out;
  logic              dt_valid;

  dt_estimator dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .T_cur  (T_cur),
    .alpha  (alpha),
    .k_dt   (k_dt),
    .d_max  (d_max),
    .init   (init),
    .dT_out (dT_out),
    .dt_valid(dt_valid)
  );

  // =========================
  // Reference model (Q0.7) — zgodny 1:1 z RTL
  // =========================
  function automatic logic signed [8:0] sxt8(input logic signed [7:0] x);
    return {x[7], x};
  endfunction

  logic signed [7:0]  T_prev_ref;
  logic signed [15:0] dT_prev_q15_ref;   // Q0.7 in Q1.15 container

  task automatic ref_reset();
    T_prev_ref        = '0;
    dT_prev_q15_ref   = '0;
  endtask

  task automatic ref_init(input logic signed [7:0] T_cur_i);
    T_prev_ref        = T_cur_i; // capture current T
    dT_prev_q15_ref   = '0;
  endtask

  function automatic logic signed [15:0] clip_q15(
    input logic signed [15:0] x,
    input logic        [7:0]  dmax // Q7.0
  );
    logic signed [15:0] lim;
    begin
      lim = {dmax,7'd0}; // Q0.7 clamp
      if (x >  lim) return lim;
      if (x < -lim) return -lim;
      return x;
    end
  endfunction

  // Jeden krok EMA; zwraca nową wartość Q0.7 w Q1.15 kontenerze
  function automatic logic signed [15:0] ema_step(
    input logic signed [7:0]  T_prev_i,
    input logic signed [7:0]  T_cur_i,
    input logic        [7:0]  alpha_i,   // Q8.8 fraction (/256)
    input logic        [7:0]  kdt_i,     // shift
    input logic        [7:0]  dmax_i     // Q7.0
  );
    logic signed [8:0]  delta_q8;
    logic signed [15:0] delta_q15, delta_scaled;
    logic [15:0]        alpha_q, one_q, inv_a;
    logic signed [31:0] term1, term2, sum32;
    logic signed [15:0] dT_new_q15;

    begin
      delta_q8     = sxt8(T_cur_i) - sxt8(T_prev_i); // Q8.0
      delta_q15    = {delta_q8, 7'b0};               // *128 => Q0.7 in Q1.15
      delta_scaled = delta_q15 >>> kdt_i;            // /2^k
      alpha_q      = {8'b0, alpha_i};               // Q8.8
      one_q        = 16'd256;
      inv_a        = one_q - alpha_q;

      term1        = $signed(dT_prev_q15_ref) * $signed({inv_a, 8'b0});
      term2        = $signed(delta_scaled)     * $signed({alpha_q, 8'b0});
      sum32        = term1 + term2;
      dT_new_q15   = sum32[31:16];                   // Q0.7 (w Q1.15 pojemniku)
      return clip_q15(dT_new_q15, dmax_i);
    end
  endfunction

  // Porównanie z tolerancją 1 LSB (Q0.7 -> 1 LSB = 1)
  task automatic expect_match(
    input logic signed [7:0] d_ref, input logic signed [7:0] d_dut, string msg
  );
    int diff;
    begin
      diff = (d_ref - d_dut);
      if (diff < 0) diff = -diff;
      assert(diff <= 1) else $fatal("%s: exp=%0d got=%0d", msg, d_ref, d_dut);
    end
  endtask

  // =========================
  // Test sequence
  // =========================
  initial begin
    // Init defaults
    alpha=8'd64; k_dt=8'd1; d_max=8'd50; init=0; T_cur=0;
    ref_reset();

    // Reset DUT
    rst_n=0; repeat(2) @(posedge clk);
    rst_n=1; @(posedge clk);

    // REQ-062: INIT — zeruje i nie podaje glitche na wyjściu
    T_cur = 8'sd10; init=1; @(posedge clk); init=0; @(posedge clk);
    ref_init(T_cur);
    assert(dt_valid==0 && dT_out==0) else $fatal("REQ-062: init not zeroing");

    // Pierwsza próbka bez zmiany T -> dT ≈ 0
    T_cur = 8'sd10; @(posedge clk);
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    assert(dt_valid==1) else $fatal("REQ-060: dt_valid not asserted");
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-060 zero delta");

    // Skok +20 przy k_dt=1 -> oczekuj dodatniego dT
    T_cur = 8'sd30; @(posedge clk);
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    assert(dT_out > 0) else $fatal("REQ-061: sign +");
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-061 +step");

    // Clamp: d_max ma ograniczać do ±8
    d_max = 8'd8;
    T_cur = 8'sd127; @(posedge clk);
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    assert( (dT_out <= 8'sd8) && (dT_out >= -8'sd8) ) else $fatal("REQ-061: clamp ±8");
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-061 clamp match");

    // Ujemny skok
    T_cur = -8'sd50; @(posedge clk);
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    assert(dT_out < 0) else $fatal("REQ-060: sign -");
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-060 -step");

    // Ekstrema alfa: alpha=0 -> stała (trzyma poprzednie dT)
    alpha = 8'd0;
    T_cur = -8'sd10; @(posedge clk);
    // ręcznie: bez zmian dT_prev_q15_ref (bo alpha=0)
    // model: krok z alpha=0
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-061 alpha=0 hold");

    // alpha=255 -> prawie podąża za delta_scaled
    alpha = 8'd255; k_dt=8'd0; d_max=8'd64;
    T_cur = 8'sd64; @(posedge clk);
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-061 alpha≈1, k=0");

    // Ekstremum k_dt: k=7 (najmniejsza skala)
    k_dt = 8'd7;
    T_cur = 8'sd66; @(posedge clk);
    dT_prev_q15_ref = ema_step(T_prev_ref, T_cur, alpha, k_dt, d_max);
    T_prev_ref      = T_cur;
    expect_match(dT_prev_q15_ref[14:7], dT_out, "REQ-061 k_dt=7");

    $display("tb_dt_estimator: PASS");
    $finish;
  end
endmodule
