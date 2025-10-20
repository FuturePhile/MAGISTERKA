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

  initial begin
    // REQ-062: hold in reset
    alpha=8'd64; k_dt=8'd1; d_max=8'd50; init=0; T_cur=0;
    #1 rst_n=0; repeat(2) @(posedge clk);
    rst_n=1; @(posedge clk);

    // INIT: capture T_cur and zero output
    T_cur = 8'sd10; init=1; @(posedge clk); init=0; @(posedge clk);
    assert(dt_valid==0 && dT_out==0) else $fatal("REQ-062 FAIL: init not zeroing");

    // Next sample same T -> delta=0 -> dT_out remains ~0
    T_cur = 8'sd10; @(posedge clk);
    assert(dt_valid==1 && dT_out==0) else $fatal("REQ-060 FAIL: zero delta");

    // Positive step: T increases by +20; with k_dt=1, delta_scaled ≈ 10 (Q0.7)
    T_cur = 8'sd30; @(posedge clk);
    assert(dT_out >= 8'sd5) else $fatal("REQ-061 FAIL: EMA too small");

    // Clamp: set d_max small and big jump
    d_max = 8'd8;  // clamp at ±8
    T_cur = 8'sd127; @(posedge clk);
    assert( (dT_out <= 8'sd8) && (dT_out >= -8'sd8) ) else $fatal("REQ-061 FAIL: clamp");

    // Negative step
    T_cur = -8'sd50; @(posedge clk);
    assert(dT_out < 0) else $fatal("REQ-060 FAIL: sign of dT");

    $display("tb_dt_estimator: PASS");
    $finish;
  end
endmodule
