`timescale 1ns/1ps

module tb_trapezoid;
  // REQ-020, REQ-210: trapezoid/triangle MF, Q7.0 in, Q1.15 out
  logic  signed [7:0] x, a, b, c, d;
  logic         [15:0] mu;

  trapezoid dut (
    .x(x), .a(a), .b(b), .c(c), .d(d),
    .mu(mu)
  );

  // Helpers
  function int mu_pct(input [15:0] mu_q15);
    return (mu_q15 * 100) >>> 15;
  endfunction

  // Check monotonicity on a closed integer range
  task automatic check_monotonic_inc(input signed [7:0] x0, input signed [7:0] x1);
    int prev, curr;
    begin
      prev = -1; // sentinel below 0%
      for (x = x0; x <= x1; x++) begin
        #1;
        curr = mu_pct(mu);
        assert(curr >= prev)
          else $fatal("REQ-020 FAIL: non-increasing on left slope at x=%0d (prev=%0d, curr=%0d)", x, prev, curr);
        prev = curr;
      end
    end
  endtask

  task automatic check_monotonic_dec(input signed [7:0] x0, input signed [7:0] x1);
    int prev, curr;
    begin
      prev = 101; // sentinel above 100%
      for (x = x0; x <= x1; x++) begin
        #1;
        curr = mu_pct(mu);
        assert(curr <= prev)
          else $fatal("REQ-020 FAIL: non-decreasing on right slope at x=%0d (prev=%0d, curr=%0d)", x, prev, curr);
        prev = curr;
      end
    end
  endtask

  initial begin
    // ---------------- Triangle centered at 0 (your original case) ----------------
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

    // ---------------- Exact boundary checks ----------------
    x = a; #1; assert(mu == 16'd0)      else $fatal("REQ-020 FAIL: mu(a) != 0");
    x = b; #1; assert(mu >= 16'h7F00)   else $fatal("REQ-020 FAIL: mu(b) not ~1");
    x = c; #1; assert(mu >= 16'h7F00)   else $fatal("REQ-020 FAIL: mu(c) not ~1");
    x = d; #1; assert(mu == 16'd0)      else $fatal("REQ-020 FAIL: mu(d) != 0");

    // ---------------- Proper trapezoid with plateau ----------------
    a = -8'sd64; b = -8'sd16; c = 8'sd16; d = 8'sd64;

    // Monotonic left slope [a..b]
    check_monotonic_inc(a, b);

    // Plateau [b..c] ~ 100%
    x = b; #1; assert(mu >= 16'h7F00);
    x = c; #1; assert(mu >= 16'h7F00);

    // Monotonic right slope [c..d]
    check_monotonic_dec(c, d);

    // ---------------- Degenerate slope guards (a==b) and (c==d) ----------------
    // Left vertical edge (a==b): should behave like a step to plateau; no divide-by-zero glitch.
    a = -8'sd32; b = -8'sd32; c = 8'sd16; d = 8'sd64;
    x = a;      #1; assert(mu >= 16'h7F00) else $fatal("REQ-020 FAIL: a==b, mu(a) should be ~1");
    x = a - 1;  #1; assert(mu == 16'd0)    else $fatal("REQ-020 FAIL: a==b, below a should be 0");
    x = a + 10; #1; assert(mu >= 16'h4000) else $fatal("REQ-020 FAIL: a==b, near left plateau too small");

    // Right vertical edge (c==d)
    a = -8'sd64; b = -8'sd16; c = 8'sd32; d = 8'sd32;
    x = d;      #1; assert(mu >= 16'h7F00) else $fatal("REQ-020 FAIL: c==d, mu(d) should be ~1");
    x = d + 1;  #1; assert(mu == 16'd0)    else $fatal("REQ-020 FAIL: c==d, above d should be 0");
    x = d - 10; #1; assert(mu >= 16'h4000) else $fatal("REQ-020 FAIL: c==d, near right plateau too small");

    $display("tb_trapezoid: PASS");
    $finish;
  end
endmodule
