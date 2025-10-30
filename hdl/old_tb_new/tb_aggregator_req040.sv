// tb_aggregator_req040.sv — lightweight TB for aggregator.sv
// REQ-040: compute S_w = Σ w_ij and S_wg = Σ (w_ij * g_ij)
// REQ-050: supports 4-rule (corners) and 9-rule mode via reg_mode
// REQ-210: internal Q1.15 arithmetic; check for saturation and rounding
// Style: module → signals → DUT → functions/tasks → initial/always

`timescale 1ns/1ps
module tb_aggregator_req040;
  timeunit 1ns; timeprecision 1ps;

  // === Signals ===
  // Inputs
  logic        reg_mode; // 0: corners only, 1: full 3x3
  logic [15:0] w00, w01, w02,
               w10, w11, w12,
               w20, w21, w22;       // Q1.15 weights (0..32767)
  logic [7:0]  g00, g01, g02,
               g10, g11, g12,
               g20, g21, g22;       // singletons in percent (0..100)

  // Outputs
  logic [15:0] S_w, S_wg;           // Q1.15

  // TB control
  bit     verbose;
  integer i;

  // === DUT instantiation ===
  aggregator dut (
    .reg_mode(reg_mode),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22),
    .g00(g00), .g01(g01), .g02(g02),
    .g10(g10), .g11(g11), .g12(g12),
    .g20(g20), .g21(g21), .g22(g22),
    .S_w(S_w), .S_wg(S_wg)
  );

  // === Reference helpers (bit-accurate to aggregator.sv) ===
  function automatic [15:0] g2q15_pct(input [7:0] gpct);
    // tmp = round(gpct * 32767 / 100), clamped to 32767
    logic [31:0] tmp;
    begin
      tmp = (gpct * 32'd32767) + 32'd50; // +0.5 for /100 rounding
      tmp = tmp / 32'd100;
      g2q15_pct = (tmp > 32'd32767) ? 16'd32767 : tmp[15:0];
    end
  endfunction

  function automatic [15:0] w_mul_g_q15(input [15:0] wq15, input [7:0] gpct);
    // (Q1.15 * Q1.15) >> 15 with rounding (add 0.5 LSB before shift)
    logic [31:0] mul;
    logic [31:0] num;
    begin
      mul = wq15 * g2q15_pct(gpct);            // up to ~ (32767^2) < 2^31
      num = mul + (32'd1 << 14);               // HALF_LSB for rounding
      w_mul_g_q15 = (num >> 15);               // back to Q1.15
      if (w_mul_g_q15 > 16'd32767) w_mul_g_q15 = 16'd32767; // safety
    end
  endfunction

  function automatic bit is_active(input int r, input int c, input logic mode);
    // active positions: corners always; edges+center only when mode==1
    // corners: (0,0),(0,2),(2,0),(2,2)
    if ((r==0 && c==0) || (r==0 && c==2) || (r==2 && c==0) || (r==2 && c==2)) return 1;
    return mode ? 1 : 0;
  endfunction

  task automatic ref_compute(
    input  logic        mode,
    input  logic [15:0] lw00, lw01, lw02,
           logic [15:0] lw10, lw11, lw12,
           logic [15:0] lw20, lw21, lw22,
    input  logic [7:0]  lg00, lg01, lg02,
           logic [7:0]  lg10, lg11, lg12,
           logic [7:0]  lg20, lg21, lg22,
    output logic [15:0] exp_Sw,
    output logic [15:0] exp_Swg
  );
    logic [19:0] sumw; // wide accumulators (9*32767 ≈ 294,903 < 2^20)
    logic [19:0] sumg;
    sumw = 20'd0; sumg = 20'd0;

    // iterate 3x3 grid manually (unrolled for clarity/bit-accuracy)
    if (is_active(0,0,mode)) begin sumw += lw00; sumg += w_mul_g_q15(lw00, lg00); end
    if (is_active(0,1,mode)) begin sumw += lw01; sumg += w_mul_g_q15(lw01, lg01); end
    if (is_active(0,2,mode)) begin sumw += lw02; sumg += w_mul_g_q15(lw02, lg02); end
    if (is_active(1,0,mode)) begin sumw += lw10; sumg += w_mul_g_q15(lw10, lg10); end
    if (is_active(1,1,mode)) begin sumw += lw11; sumg += w_mul_g_q15(lw11, lg11); end
    if (is_active(1,2,mode)) begin sumw += lw12; sumg += w_mul_g_q15(lw12, lg12); end
    if (is_active(2,0,mode)) begin sumw += lw20; sumg += w_mul_g_q15(lw20, lg20); end
    if (is_active(2,1,mode)) begin sumw += lw21; sumg += w_mul_g_q15(lw21, lg21); end
    if (is_active(2,2,mode)) begin sumw += lw22; sumg += w_mul_g_q15(lw22, lg22); end

    // saturate back to Q1.15 as DUT does
    exp_Sw  = (sumw > 20'd32767) ? 16'd32767 : sumw[15:0];
    exp_Swg = (sumg > 20'd32767) ? 16'd32767 : sumg[15:0];
  endtask

  task automatic drive_all(
    input logic        mode,
    input logic [15:0] lw00, lw01, lw02,
          logic [15:0] lw10, lw11, lw12,
          logic [15:0] lw20, lw21, lw22,
    input logic [7:0]  lg00, lg01, lg02,
          logic [7:0]  lg10, lg11, lg12,
          logic [7:0]  lg20, lg21, lg22
  );
    reg_mode = mode;
    w00=lw00; w01=lw01; w02=lw02;
    w10=lw10; w11=lw11; w12=lw12;
    w20=lw20; w21=lw21; w22=lw22;
    g00=lg00; g01=lg01; g02=lg02;
    g10=lg10; g11=lg11; g12=lg12;
    g20=lg20; g21=lg21; g22=lg22;
  endtask

  task automatic check_now(string tag);
    logic [15:0] eSw, eSwg;
    #1ns; // combinational settle
    ref_compute(reg_mode,
      w00,w01,w02, w10,w11,w12, w20,w21,w22,
      g00,g01,g02, g10,g11,g12, g20,g21,g22,
      eSw, eSwg);

    if (S_w  !== eSw ) $error("[REQ-040] %s S_w  mismatch got=%0d exp=%0d", tag, S_w,  eSw);
    if (S_wg !== eSwg) $error("[REQ-040] %s S_wg mismatch got=%0d exp=%0d", tag, S_wg, eSwg);

    if (verbose)
      $display("INFO: [REQ-040] %s mode=%0d | S_w=%0d S_wg=%0d", tag, reg_mode, S_w, S_wg);
  endtask

  // === Test flow ===
  initial begin
    verbose = $test$plusargs("verbose");

    // Case A: 4-rule mode (corners only)
    drive_all(1'b0,
      16'd1000, 16'd2000, 16'd3000,
      16'd4000, 16'd5000, 16'd6000,
      16'd7000, 16'd8000, 16'd9000,
      8'd10, 8'd20, 8'd30,
      8'd40, 8'd50, 8'd60,
      8'd70, 8'd80, 8'd90);
    check_now("A1 corners-only");

    // Case B: 9-rule mode (all active)
    drive_all(1'b1,
      16'd1000, 16'd2000, 16'd3000,
      16'd4000, 16'd5000, 16'd6000,
      16'd7000, 16'd8000, 16'd9000,
      8'd10, 8'd20, 8'd30,
      8'd40, 8'd50, 8'd60,
      8'd70, 8'd80, 8'd90);
    check_now("B1 full-3x3");

    // Case C: saturation of S_w (sum of 9 weights)
    drive_all(1'b1,
      16'd32767,16'd32767,16'd32767,
      16'd32767,16'd32767,16'd32767,
      16'd32767,16'd32767,16'd32767,
      8'd0,8'd0,8'd0, 8'd0,8'd0,8'd0, 8'd0,8'd0,8'd0);
    check_now("C1 sat S_w");

    // Case D: saturation of S_wg (max weights & 100%)
    drive_all(1'b1,
      16'd32767,16'd32767,16'd32767,
      16'd32767,16'd32767,16'd32767,
      16'd32767,16'd32767,16'd32767,
      8'd100,8'd100,8'd100, 8'd100,8'd100,8'd100, 8'd100,8'd100,8'd100);
    check_now("D1 sat S_wg");

    // Case E: 4-rule with non-zero centers/edges (should be gated to zero)
    drive_all(1'b0,
      16'd0, 16'd1000, 16'd0,
      16'd1000,16'd5000,16'd1000,
      16'd0, 16'd1000, 16'd0,
      8'd50,8'd50,8'd50, 8'd50,8'd50,8'd50, 8'd50,8'd50,8'd50);
    check_now("E1 gate non-corners in 4-rule");

    // Case F: random sanity (20 samples)
    for (i=0; i<20; i++) begin
      reg_mode = $urandom_range(0,1);
      w00=$urandom_range(0,32767); w01=$urandom_range(0,32767); w02=$urandom_range(0,32767);
      w10=$urandom_range(0,32767); w11=$urandom_range(0,32767); w12=$urandom_range(0,32767);
      w20=$urandom_range(0,32767); w21=$urandom_range(0,32767); w22=$urandom_range(0,32767);
      g00=$urandom_range(0,100); g01=$urandom_range(0,100); g02=$urandom_range(0,100);
      g10=$urandom_range(0,100); g11=$urandom_range(0,100); g12=$urandom_range(0,100);
      g20=$urandom_range(0,100); g21=$urandom_range(0,100); g22=$urandom_range(0,100);
      if (verbose) $display("INFO: [REQ-040][RAND] mode=%0d | w00=%0d w01=%0d w02=%0d w10=%0d w11=%0d w12=%0d w20=%0d w21=%0d w22=%0d | g00=%0d..g22=%0d",
                            reg_mode, w00,w01,w02,w10,w11,w12,w20,w21,w22, g00,g22);
      check_now("F rand");
    end

    $display("[REQ-040][REQ-050][REQ-210] aggregator TB finished");
    $finish;
  end
endmodule
