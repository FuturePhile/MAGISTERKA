// tb_fuzzifier_t_req020.sv — lightweight TB for fuzzifier_T.sv
// REQ-020/210: three MFs (neg/zero/pos), Q7.0 params, outputs Q1.15 in [0..1]
// Style: portable, English comments, variables at top, ordered sections.

`timescale 1ns/1ps
module tb_fuzzifier_t_req020;
  timeunit 1ns; timeprecision 1ps;

  // === Signals (I/O mirrors + temps) ===
  // DUT inputs
  logic signed [7:0] x;
  logic signed [7:0] a_neg, b_neg, c_neg, d_neg;
  logic signed [7:0] a_zero, b_zero, c_zero, d_zero;
  logic signed [7:0] a_pos, b_pos, c_pos, d_pos;

  // DUT outputs
  logic [15:0] mu_neg, mu_zero, mu_pos;

  // TB control / temps
  bit     verbose;
  integer xi, i;

  // === DUT instantiation (ports per spec) ===
  fuzzifier_T dut (
    .x      (x),
    .a_neg  (a_neg),  .b_neg (b_neg),  .c_neg (c_neg),  .d_neg (d_neg),
    .a_zero (a_zero), .b_zero(b_zero), .c_zero(c_zero), .d_zero(d_zero),
    .a_pos  (a_pos),  .b_pos (b_pos),  .c_pos (c_pos),  .d_pos (d_pos),
    .mu_neg (mu_neg), .mu_zero(mu_zero), .mu_pos(mu_pos)
  );

  // === Functions / tasks ===
  function automatic logic [15:0] ref_mu (
      input logic signed [7:0] fx,
      input logic signed [7:0] fa,
      input logic signed [7:0] fb,
      input logic signed [7:0] fc,
      input logic signed [7:0] fd
  );
    logic  signed [8:0] dx1, dx2, t1, t2;
    logic         [23:0] num;
    logic         [15:0] out_mu;
    out_mu = 16'd0;
    if ((fx <= fa) || (fx >= fd))       out_mu = 16'd0;
    else if ((fx >= fb) && (fx <= fc))  out_mu = 16'h7FFF;
    else if (fx > fa && fx < fb) begin
      dx1 = $signed(fb) - $signed(fa); if (dx1 == 0) dx1 = 1;
      t1  = $signed(fx) - $signed(fa);
      num = $unsigned(t1) << 15; out_mu = num / $unsigned(dx1);
    end else begin
      dx2 = $signed(fd) - $signed(fc); if (dx2 == 0) dx2 = 1;
      t2  = $signed(fd) - $signed(fx);
      num = $unsigned(t2) << 15; out_mu = num / $unsigned(dx2);
    end
    if (out_mu > 16'h7FFF) out_mu = 16'h7FFF;
    return out_mu;
  endfunction

  task automatic set_params_default();
    a_neg  = -128; b_neg  = -64;  c_neg  = -32;  d_neg  = 0;
    a_zero = -16;  b_zero = 0;    c_zero = 0;    d_zero = 16;  // triangle
    a_pos  = 0;    b_pos  = 32;   c_pos  = 64;   d_pos  = 127;
  endtask

  task automatic check_all(input integer xt);
    logic [15:0] rN, rZ, rP;
    x = xt[7:0]; #1ns;
    rN = ref_mu(x, a_neg,  b_neg,  c_neg,  d_neg);
    rZ = ref_mu(x, a_zero, b_zero, c_zero, d_zero);
    rP = ref_mu(x, a_pos,  b_pos,  c_pos,  d_pos);
    if (mu_neg  !== rN ) $error("[REQ-020] mu_neg mismatch x=%0d got=%0d exp=%0d", $signed(x), mu_neg,  rN);
    if (mu_zero !== rZ ) $error("[REQ-020] mu_zero mismatch x=%0d got=%0d exp=%0d", $signed(x), mu_zero, rZ);
    if (mu_pos  !== rP ) $error("[REQ-020] mu_pos mismatch x=%0d got=%0d exp=%0d",  $signed(x), mu_pos,  rP);
    if (mu_neg > 16'h7FFF || mu_zero > 16'h7FFF || mu_pos > 16'h7FFF)
      $error("[REQ-210] overflow detected at x=%0d", $signed(x));
    if (verbose) $display("INFO: [REQ-020] x=%0d | muN=%0d muZ=%0d muP=%0d", $signed(x), mu_neg, mu_zero, mu_pos);
  endtask

  // === Initial / always ===
  initial begin
    verbose = $test$plusargs("verbose");

    // Case A: defaults + directed
    set_params_default();
    check_all(-128); check_all(127);
    for (xi = -64; xi <= -32; xi += 8)  check_all(xi);   // NEG plateau
    for (xi = -16; xi <=  16; xi += 2)  check_all(xi);   // ZERO triangle
    for (xi =   0; xi <= 127; xi += 16) check_all(xi);   // POS sweep

    // Case B: shifted sets
    a_neg=-100; b_neg=-70; c_neg=-50; d_neg=-20;
    a_zero=-25; b_zero=-5; c_zero=-5; d_zero=25;
    a_pos=10;   b_pos=30;  c_pos=40;  d_pos=60;
    for (i = -110; i <= 70; i += 10) check_all(i);

    // Case C: light random
    for (i = 0; i < 20; i++) begin
      a_neg = $urandom_range(-128,-60);
      b_neg = a_neg + $urandom_range(0,25);
      c_neg = b_neg + $urandom_range(0,25);
      d_neg = c_neg + $urandom_range(0,25);

      a_zero = $urandom_range(-20,0); b_zero=0; c_zero=0; d_zero=$urandom_range(0,20);

      a_pos = $urandom_range(-5,20);
      b_pos = a_pos + $urandom_range(0,25);
      c_pos = b_pos + $urandom_range(0,25);
      d_pos = c_pos + $urandom_range(0,25);

      check_all($urandom_range(-128,127));
      check_all($urandom_range(-128,127));
    end

    $display("[REQ-020][REQ-210] fuzzifier_T TB finished");
    $finish;
  end
endmodule
