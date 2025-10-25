// tb_trapezoid_req020.sv — lightweight unit testbench for trapezoid.sv
// REQ-020: trapezoidal/triangular MF; μ in [0,1] (Q1.15); shape per (a..d)
// REQ-210: datapath Q1.15; no overflow; correct boundary handling
// Tool: Questa/ModelSim (SystemVerilog). File name kept portable (Linux/Windows).

`timescale 1ns/1ps

module tb_trapezoid_req020;
  timeunit 1ns; timeprecision 1ps;

  // === DUT ports (Q7.0 for inputs, Q1.15 for output) ===
  logic signed [7:0] x, a, b, c, d; 
  logic        [15:0] mu;         

  // === Loop/temporary variables declared at module scope (portability/style) ===
  integer xi;           // generic loop counter for x sweeps
  integer k;            // random case iterator
  integer t;            // inner loop
  integer ia, ib, ic, id; // temporary parameters for MF
  integer ix;           // temporary x input for randomized tests

  // === DUT instantiation ===
  trapezoid dut (
    .x(x), .a(a), .b(b), .c(c), .d(d), .mu(mu)
  );

  // === Simple bit-accurate reference model (matches DUT arithmetic) ===
  function automatic logic [15:0] ref_mu (
      input logic signed [7:0] fx,
      input logic signed [7:0] fa,
      input logic signed [7:0] fb,
      input logic signed [7:0] fc,
      input logic signed [7:0] fd
  );
    logic [8:0]  dx1, dx2, n1, n2, t1, t2; // helper deltas (unsigned)
    logic [15:0] out_mu;
    out_mu = 16'd0;

    if ((fx <= fa) || (fx >= fd)) begin
      out_mu = 16'd0;
    end else if ((fx >= fb) && (fx <= fc)) begin
      out_mu = 16'h7FFF; // 1.0 in Q1.15
    end else if ((fx > fa) && (fx < fb)) begin
      dx1 = $unsigned($signed(fb) - $signed(fa));
      t1  = $unsigned($signed(fx) - $signed(fa));
      n1  = (dx1 == 0) ? 9'd1 : dx1;
      // scale t1 from Q7.0 to Q1.15 using <<15 / n1 (implemented via left shift then divide)
      out_mu = ( {7'd0, t1} << 8 ) << 8; // Q1.15 numerator pre-div
      out_mu = out_mu / n1;              // truncation
    end else begin
      dx2 = $unsigned($signed(fd) - $signed(fc));
      t2  = $unsigned($signed(fd) - $signed(fx));
      n2  = (dx2 == 0) ? 9'd1 : dx2;
      out_mu = ( {7'd0, t2} << 8 ) << 8; // Q1.15 numerator pre-div
      out_mu = out_mu / n2;
    end
    return out_mu;
  endfunction

  // === Small helper tasks (no local variable declarations inside initial) ===
  task automatic apply_params(input integer pa, input integer pb, input integer pc, input integer pd);
    a = pa[7:0]; b = pb[7:0]; c = pc[7:0]; d = pd[7:0];
  endtask

  task automatic check_point(input integer px);
    logic [15:0] exp_mu;
    x      = px[7:0];
    #1ns; // allow combinational settle
    exp_mu = ref_mu(x,a,b,c,d);
    // REQ-210: no overflow beyond 1.0 (Q1.15)
    if (mu > 16'h7FFF) begin
      $error("[REQ-210] mu overflow: got=%0d at x=%0d", mu, $signed(x));
    end
    // REQ-020: exact match to reference (bit-accurate model)
    if (mu !== exp_mu) begin
      $error("[REQ-020] mismatch x=%0d a=%0d b=%0d c=%0d d=%0d got=%0d exp=%0d",
             $signed(x),$signed(a),$signed(b),$signed(c),$signed(d), mu, exp_mu);
    end
  endtask

  // === Minimal test scenarios ===
  initial begin
    // Case 1: Regular trapezoid
    apply_params(0,10,20,30);
    // outside left/right
    check_point(-20);
    check_point(40);
    // left slope
    for (xi = 1; xi < 10; xi = xi + 1) check_point(xi);
    // plateau
    for (xi = 10; xi <= 20; xi = xi + 1) check_point(xi);
    // right slope
    for (xi = 21; xi < 30; xi = xi + 1) check_point(xi);

    // Case 2: Triangle (b==c)
    apply_params(-10,0,0,15);
    for (xi = -20; xi <= 25; xi = xi + 1) check_point(xi);

    // Case 3: Degenerate widths
    // 3a) b==a
    apply_params(5,5,12,25);
    for (xi = -5; xi <= 30; xi = xi + 1) check_point(xi);
    // 3b) c==d
    apply_params(-15,-10,5,5);
    for (xi = -30; xi <= 10; xi = xi + 1) check_point(xi);

    // Case 4: Light randomized sampling (reproducible if you set a seed in vsim)
    for (k = 0; k < 20; k = k + 1) begin
      ia = $urandom_range(-128, 120);
      ib = ia + $urandom_range(0, 20);
      ic = ib + $urandom_range(0, 20);
      id = ic + $urandom_range(0, 20);
      apply_params(ia, ib, ic, id);
      for (t = 0; t < 6; t = t + 1) begin
        ix = $urandom_range(ia-10, id+10);
        check_point(ix);
      end
    end

    $display("[REQ-020][REQ-210] trapezoid TB finished");
    $finish;
  end
endmodule
