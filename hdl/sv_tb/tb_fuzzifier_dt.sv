// tb_fuzzifier_dt.sv - lightweight TB for fuzzifier_dT.sv
// REQ-020/210: three MFs (neg/zero/pos), Q7.0 params, outputs Q1.15 in [0..1]

`timescale 1ns/1ps
module tb_fuzzifier_dt;
  timeunit 1ns;
  timeprecision 1ps;

  // DUT inputs
  logic signed [7:0] x;
  logic signed [7:0] a_neg;
  logic signed [7:0] b_neg;
  logic signed [7:0] c_neg;
  logic signed [7:0] d_neg;
  logic signed [7:0] a_zero;
  logic signed [7:0] b_zero;
  logic signed [7:0] c_zero;
  logic signed [7:0] d_zero;
  logic signed [7:0] a_pos;
  logic signed [7:0] b_pos;
  logic signed [7:0] c_pos;
  logic signed [7:0] d_pos;

  // DUT outputs
  logic [15:0] mu_neg;
  logic [15:0] mu_zero;
  logic [15:0] mu_pos;

  // TB control / temps
  bit verbose;
  integer xi;
  integer i;

  // DUT instantiation
  fuzzifier_dT dut (
    .x(x),
    .a_neg(a_neg),
    .b_neg(b_neg),
    .c_neg(c_neg),
    .d_neg(d_neg),
    .a_zero(a_zero),
    .b_zero(b_zero),
    .c_zero(c_zero),
    .d_zero(d_zero),
    .a_pos(a_pos),
    .b_pos(b_pos),
    .c_pos(c_pos),
    .d_pos(d_pos),
    .mu_neg(mu_neg),
    .mu_zero(mu_zero),
    .mu_pos(mu_pos)
  );

  // Bit-accurate reference for a single trapezoid
  function automatic logic [15:0] ref_mu(
    input logic signed [7:0] fx,
    input logic signed [7:0] fa,
    input logic signed [7:0] fb,
    input logic signed [7:0] fc,
    input logic signed [7:0] fd
  );
    logic signed  [8:0] dx1;
    logic signed  [8:0] dx2;
    logic signed  [8:0] t1;
    logic signed  [8:0] t2;
    logic         [23:0] num;
    logic         [15:0] out_mu;

    out_mu = 16'd0;

    if ((fx <= fa) || (fx >= fd)) begin
      out_mu = 16'd0;
    end else if ((fx >= fb) && (fx <= fc)) begin
      out_mu = 16'h7FFF;
    end else if ((fx > fa) && (fx < fb)) begin
      dx1 = $signed(fb) - $signed(fa);
      if (dx1 == 0) dx1 = 1;
      t1  = $signed(fx) - $signed(fa);
      num = $unsigned(t1);
      num = num << 15;
      out_mu = num / $unsigned(dx1);
    end else begin
      dx2 = $signed(fd) - $signed(fc);
      if (dx2 == 0) dx2 = 1;
      t2  = $signed(fd) - $signed(fx);
      num = $unsigned(t2);
      num = num << 15;
      out_mu = num / $unsigned(dx2);
    end

    if (out_mu > 16'h7FFF) out_mu = 16'h7FFF;
    return out_mu;
  endfunction

  // Helper tasks
  task automatic set_params_default();
    begin
      a_neg  = -100;
      b_neg  = -50;
      c_neg  = -30;
      d_neg  = -5;
      a_zero = -10;
      b_zero = 0;
      c_zero = 0;
      d_zero = 10;     // triangle
      a_pos  = 5;
      b_pos  = 25;
      c_pos  = 35;
      d_pos  = 60;
    end
  endtask

  task automatic check_all(input integer xt);
    logic [15:0] rN;
    logic [15:0] rZ;
    logic [15:0] rP;
    begin
      x = xt[7:0];
      #1ns;
      rN = ref_mu(x, a_neg,  b_neg,  c_neg,  d_neg);
      rZ = ref_mu(x, a_zero, b_zero, c_zero, d_zero);
      rP = ref_mu(x, a_pos,  b_pos,  c_pos,  d_pos);

      if (mu_neg  !== rN)  $error("[REQ-020] mu_neg mismatch x=%0d got=%0d exp=%0d",  $signed(x), mu_neg,  rN);
      if (mu_zero !== rZ)  $error("[REQ-020] mu_zero mismatch x=%0d got=%0d exp=%0d", $signed(x), mu_zero, rZ);
      if (mu_pos  !== rP)  $error("[REQ-020] mu_pos mismatch x=%0d got=%0d exp=%0d",  $signed(x), mu_pos,  rP);

      if ((mu_neg > 16'h7FFF) || (mu_zero > 16'h7FFF) || (mu_pos > 16'h7FFF)) $error("[REQ-210] overflow detected at x=%0d", $signed(x));

      if (verbose) $display("INFO: [REQ-020] x=%0d | muN=%0d muZ=%0d muP=%0d", $signed(x), mu_neg, mu_zero, mu_pos);
    end
  endtask

  // Scenarios
  initial begin
    verbose = $test$plusargs("verbose");

    // Case A: defaults + directed
    set_params_default();
    check_all(-128);
    check_all(127);
    for (xi = -60; xi <= -5; xi = xi + 11) check_all(xi);   // NEG region
    for (xi = -10; xi <= 10; xi = xi + 2)  check_all(xi);   // ZERO triangle
    for (xi =   5; xi <= 60; xi = xi + 11) check_all(xi);   // POS region

    // Case B: shift and tighten
    a_neg  = -120;
    b_neg  = -90;
    c_neg  = -70;
    d_neg  = -40;
    a_zero = -20;
    b_zero = 0;
    c_zero = 0;
    d_zero = 20;
    a_pos  = 0;
    b_pos  = 20;
    c_pos  = 30;
    d_pos  = 45;
    for (i = -125; i <= 80; i = i + 15) check_all(i);

    // Case C: light random
    for (i = 0; i < 20; i = i + 1) begin
      a_neg  = $urandom_range(-128, -60);
      b_neg  = a_neg + $urandom_range(0, 25);
      c_neg  = b_neg + $urandom_range(0, 25);
      d_neg  = c_neg + $urandom_range(0, 25);

      a_zero = $urandom_range(-20, 0);
      b_zero = 0;
      c_zero = 0;
      d_zero = $urandom_range(0, 20);

      a_pos  = $urandom_range(-5, 20);
      b_pos  = a_pos + $urandom_range(0, 25);
      c_pos  = b_pos + $urandom_range(0, 25);
      d_pos  = c_pos + $urandom_range(0, 25);

      $display("INFO: [REQ-020][RAND][dT] NEG:(a=%0d,b=%0d,c=%0d,d=%0d) ZERO:(a=%0d,b=%0d,c=%0d,d=%0d) POS:(a=%0d,b=%0d,c=%0d,d=%0d)",
               $signed(a_neg),  $signed(b_neg),  $signed(c_neg),  $signed(d_neg),
               $signed(a_zero), $signed(b_zero), $signed(c_zero), $signed(d_zero),
               $signed(a_pos),  $signed(b_pos),  $signed(c_pos),  $signed(d_pos));

      check_all($urandom_range(-128, 127));
      check_all($urandom_range(-128, 127));
    end

    $display("[REQ-020][REQ-210] fuzzifier_dT TB finished");
    $finish;
  end

endmodule
