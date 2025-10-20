`timescale 1ns/1ps

module tb_trapezoid;
  // REQ-020, REQ-210: verify trapezoid left/right slopes, plateau, and outside support
  logic signed [7:0] x, a,b,c,d;
  logic       [15:0] mu;

  trapezoid dut (
    .x (x),
    .a (a), .b (b), .c (c), .d (d),
    .mu(mu)
  );

  // Helpers
  function int mu_pct(input [15:0] mu_q15);
    mu_pct = (mu_q15 * 100) >>> 15;
  endfunction

  initial begin
    // Triangle centered at 0: a=-64,b=0,c=0,d=+64
    a = -8'sd64; b = 8'sd0; c = 8'sd0; d = 8'sd64;

    // Outside left
    x = -8'sd127; #1;
    assert(mu == 16'd0) else $fatal("REQ-020 FAIL: outside left");

    // Left slope at half: x = -32 -> μ ≈ 0.5
    x = -8'sd32; #1;
    assert(mu_pct(mu) >= 49 && mu_pct(mu) <= 51)
      else $fatal("REQ-020 FAIL: left slope ~0.5 got %0d%%", mu_pct(mu));

    // Plateau (triangle peak b=c=0): x=0 -> μ≈1.0
    x = 8'sd0; #1;
    assert(mu >= 16'h7F00) else $fatal("REQ-020 FAIL: plateau not ~1");

    // Right slope at half: x=+32 -> μ ≈ 0.5
    x = 8'sd32; #1;
    assert(mu_pct(mu) >= 49 && mu_pct(mu) <= 51)
      else $fatal("REQ-020 FAIL: right slope ~0.5 got %0d%%", mu_pct(mu));

    // Outside right
    x = 8'sd127; #1;
    assert(mu == 16'd0) else $fatal("REQ-020 FAIL: outside right");

    $display("tb_trapezoid: PASS");
    $finish;
  end
endmodule
