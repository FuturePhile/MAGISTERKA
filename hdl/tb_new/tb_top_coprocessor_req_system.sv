// tb_top_coprocessor_req320.sv — system-level TB for top_coprocessor
// Covers REQ-010/020/030/040/050/060/061/062/210/230/320/310 (simulation focus)
// Style: module → signals → DUT → helpers → initial/always
// Additions vs previous version:
//  - Dense directed grid over T×dT for both REG_MODEs (A/B same vectors per REQ-030)
//  - 1000 random samples (dt_mode=0) with MAE computation (REQ-310 ≤1%)
//  - dt_mode=1 stress: INIT, steady@T=0, ramp up/down, random walk; check latency, pulse width,
//    bounds, and lack of INIT spike (REQ-060/061/062/230)

`timescale 1ns/1ps
module tb_top_coprocessor_req320;
  timeunit 1ns; timeprecision 1ps;

  // === Clock / reset ===
  logic clk; logic rst_n; localparam real TCLK_NS = 10.0;
  initial begin clk = 0; forever #(TCLK_NS/2.0) clk = ~clk; end

  // === Control/data signals matching DUT ===
  logic        start;       // level; rising edge is captured internally
  logic        init;        // level; rising edge resets dt estimator
  logic        reg_mode;    // 0: 4 rules, 1: 9 rules
  logic        dt_mode;     // 0: external dT_in, 1: internal estimator
  logic signed [7:0] T_in;
  logic signed [7:0] dT_in;

  // MF thresholds (T)
  logic signed [7:0] T_neg_a, T_neg_b, T_neg_c, T_neg_d;
  logic signed [7:0] T_zero_a, T_zero_b, T_zero_c, T_zero_d;
  logic signed [7:0] T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d;
  // MF thresholds (dT)
  logic signed [7:0] dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d;
  logic signed [7:0] dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d;
  logic signed [7:0] dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d;

  // DUT outputs
  logic        valid;
  logic [7:0]  G_out;

  // TB control
  bit verbose; integer i, j;

  int lat; 
  logic [7:0] Ts[]; 
  logic [7:0] dTs[];

  int N;
  int mae_acc;
  int diff;

  logic [15:0] muTn,muTz,muTp, muDn,muDz,muDp; logic [15:0] w00,w01,w02,w10,w11,w12,w20,w21,w22; logic [19:0] sumw,sumwg; logic [7:0] Gexp;
  int latR;
  int mae;
  int lat1, latS, latU, latD, latRW;
  int step, nxt;

  // === Instantiate DUT ===
  top_coprocessor dut (
    .clk(clk), .rst_n(rst_n),
    .start(start), .init(init), .reg_mode(reg_mode), .dt_mode(dt_mode),
    .T_in(T_in), .dT_in(dT_in),
    .T_neg_a(T_neg_a), .T_neg_b(T_neg_b), .T_neg_c(T_neg_c), .T_neg_d(T_neg_d),
    .T_zero_a(T_zero_a), .T_zero_b(T_zero_b), .T_zero_c(T_zero_c), .T_zero_d(T_zero_d),
    .T_pos_a(T_pos_a), .T_pos_b(T_pos_b), .T_pos_c(T_pos_c), .T_pos_d(T_pos_d),
    .dT_neg_a(dT_neg_a), .dT_neg_b(dT_neg_b), .dT_neg_c(dT_neg_c), .dT_neg_d(dT_neg_d),
    .dT_zero_a(dT_zero_a), .dT_zero_b(dT_zero_b), .dT_zero_c(dT_zero_c), .dT_zero_d(dT_zero_d),
    .dT_pos_a(dT_pos_a), .dT_pos_b(dT_pos_b), .dT_pos_c(dT_pos_c), .dT_pos_d(dT_pos_d),
    .valid(valid), .G_out(G_out)
  );

  // === Reference helpers (bit-accurate path for DT_MODE=0) ===
  function automatic logic [15:0] ref_mu (
      input logic signed [7:0] fx,
      input logic signed [7:0] fa,
      input logic signed [7:0] fb,
      input logic signed [7:0] fc,
      input logic signed [7:0] fd
  );
    logic  signed [8:0] dx1, dx2, t1, t2;
    logic         [23:0] num; logic [15:0] out_mu;
    out_mu = 16'd0;
    if ((fx <= fa) || (fx >= fd)) out_mu = 16'd0;
    else if ((fx >= fb) && (fx <= fc)) out_mu = 16'h7FFF;
    else if (fx > fa && fx < fb) begin
      dx1 = $signed(fb) - $signed(fa); if (dx1 == 0) dx1 = 1;
      t1  = $signed(fx) - $signed(fa);
      num = $unsigned(t1) << 15; out_mu = num / $unsigned(dx1);
    end else begin
      dx2 = $signed(fd) - $signed(fc); if (dx2 == 0) dx2 = 1;
      t2  = $signed(fd) - $signed(fx);
      num = $unsigned(t2) << 15; out_mu = num / $unsigned(dx2);
    end
    if (out_mu > 16'h7FFF) out_mu = 16'h7FFF; return out_mu;
  endfunction

  function automatic logic [15:0] q15_min(input logic [15:0] a, b);
    return (a < b) ? a : b;
  endfunction

  function automatic [15:0] g2q15_pct(input [7:0] gpct);
    logic [31:0] tmp; begin tmp = (gpct * 32'd32767) + 32'd50; tmp = tmp / 32'd100; return (tmp>32'd32767)?16'd32767:tmp[15:0]; end
  endfunction

  function automatic [15:0] w_mul_g_q15(input [15:0] wq15, input [7:0] gpct);
    logic [31:0] mul, num; begin mul = wq15 * g2q15_pct(gpct); num = mul + (32'd1<<14); return (num>>15); end
  endfunction

  function automatic [7:0] ref_defuzz(input [15:0] Sw, input [15:0] Swg);
    localparam logic [15:0] EPS = 16'd1; logic [15:0] den; logic [31:0] ratio_q15, percent_u; logic [7:0] out;
    begin
      den = (Sw < EPS) ? EPS : Sw;
      ratio_q15 = ({16'd0,Swg} << 15) / den;
      percent_u = (ratio_q15 * 32'd100) >> 15;
      out = (percent_u > 32'd100) ? 8'd100 : percent_u[7:0];
      return out;
    end
  endfunction

  // Singletons (copy of DUT locals)
  localparam logic [7:0] G00=8'd100, G01=8'd50,  G02=8'd30,
                         G10=8'd50,  G11=8'd50,  G12=8'd50,
                         G20=8'd80,  G21=8'd50,  G22=8'd0;

  // === Tasks ===
  task automatic set_mf_defaults();
    // T sets
    T_neg_a=-128; T_neg_b=-64;  T_neg_c=-32;  T_neg_d=0;
    T_zero_a=-16; T_zero_b=0;   T_zero_c=0;   T_zero_d=16;
    T_pos_a=0;   T_pos_b=32;   T_pos_c=64;   T_pos_d=127;
    // dT sets
    dT_neg_a=-100; dT_neg_b=-50; dT_neg_c=-30; dT_neg_d=-5;
    dT_zero_a=-10; dT_zero_b=0;  dT_zero_c=0;  dT_zero_d=10;
    dT_pos_a=5;    dT_pos_b=25;  dT_pos_c=35;  dT_pos_d=60;
  endtask

  task automatic pulse_start(); begin @(negedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0; end endtask
  task automatic pulse_init();  begin @(negedge clk); init  <= 1'b1; @(posedge clk); init  <= 1'b0; end endtask

  task automatic wait_valid_count_cycles(output int cnt);
    cnt = 0;
    while (!valid) begin @(posedge clk); cnt++; if (cnt>32) break; end
  endtask

  task automatic check_valid_one_shot();
    // valid must be 1-cycle pulse
    if (!valid) @(posedge clk); // align to a cycle after becoming high
    assert (valid) else $error("[REQ-230] valid not high when expected");
    @(posedge clk);
    assert (!valid) else $error("[REQ-230] valid must be a 1-cycle pulse");
  endtask

  task automatic compute_and_check_expected(string tag);
    // Only for dt_mode=0
    logic [15:0] muTn,muTz,muTp, muDn,muDz,muDp;
    logic [15:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;
    logic [19:0] sumw,sumwg; logic [7:0] Gexp;
    // Fuzzify
    muTn=ref_mu(T_in,T_neg_a,T_neg_b,T_neg_c,T_neg_d);
    muTz=ref_mu(T_in,T_zero_a,T_zero_b,T_zero_c,T_zero_d);
    muTp=ref_mu(T_in,T_pos_a, T_pos_b, T_pos_c, T_pos_d);

    muDn=ref_mu(dT_in,dT_neg_a,dT_neg_b,dT_neg_c,dT_neg_d);
    muDz=ref_mu(dT_in,dT_zero_a,dT_zero_b,dT_zero_c,dT_zero_d);
    muDp=ref_mu(dT_in,dT_pos_a, dT_pos_b, dT_pos_c, dT_pos_d);

    // rules (min)
    w00=q15_min(muTn,muDn); w01=q15_min(muTn,muDz); w02=q15_min(muTn,muDp);
    w10=q15_min(muTz,muDn); w11=q15_min(muTz,muDz); w12=q15_min(muTz,muDp);
    w20=q15_min(muTp,muDn); w21=q15_min(muTp,muDz); w22=q15_min(muTp,muDp);

    // aggregation with reg_mode
    sumw=20'd0; sumwg=20'd0;
    // corners always
    sumw += w00; sumwg += w_mul_g_q15(w00,G00);
    sumw += w02; sumwg += w_mul_g_q15(w02,G02);
    sumw += w20; sumwg += w_mul_g_q15(w20,G20);
    sumw += w22; sumwg += w_mul_g_q15(w22,G22);
    if (reg_mode) begin
      sumw += w01; sumwg += w_mul_g_q15(w01,G01);
      sumw += w10; sumwg += w_mul_g_q15(w10,G10);
      sumw += w11; sumwg += w_mul_g_q15(w11,G11);
      sumw += w12; sumwg += w_mul_g_q15(w12,G12);
      sumw += w21; sumwg += w_mul_g_q15(w21,G21);
    end
    // saturate like DUT
    if (sumw  > 20'd32767) sumw  = 20'd32767;
    if (sumwg > 20'd32767) sumwg = 20'd32767;

    Gexp = ref_defuzz(sumw[15:0], sumwg[15:0]);

    // Drive and check
    pulse_start();
    wait_valid_count_cycles(lat);
    assert (lat <= 10) else $error("[REQ-230] %s latency=%0d > 10", tag, lat);
    check_valid_one_shot();
    @(posedge clk); // read registered G_out
    if (G_out !== Gexp)
      $error("[REQ-010] %s G_out mismatch got=%0d exp=%0d (lat=%0d)", tag, G_out, Gexp, lat);
    if (verbose) $display("INFO: [SYS] %s reg_mode=%0d dt_mode=%0d | lat=%0d | G=%0d (exp %0d)", tag, reg_mode, dt_mode, lat, G_out, Gexp);
  endtask

  // === Test flow ===
  initial begin
    verbose = $test$plusargs("verbose");

    // Reset
    start=0; init=0; reg_mode=0; dt_mode=0; set_mf_defaults(); T_in=0; dT_in=0;
    rst_n=0; repeat (3) @(posedge clk); rst_n=1; @(posedge clk);

    // --- Block 1: DT_MODE=0, dense directed grid + A/B on same vectors (REQ-010/020/030/040/050/210) ---
    dt_mode = 1'b0; // external dT
    Ts      [0:9] = '{-128,-64,-32,-16,0,16,32,64,96,127};
    dTs     [0:6] = '{-60,-30,-10,0,10,30,60};

    // reg_mode = 0 and 1 on the SAME vector set (REQ-030)
    for (int rm = 0; rm <= 1; rm++) begin : REG_AB
      reg_mode = rm[0]; // 0 then 1
      for (i = 0; i < 10; i++) begin
        for (j = 0; j < 7; j++) begin
          T_in  = Ts[i][7:0];
          dT_in = dTs[j][7:0];
          compute_and_check_expected($sformatf("Grid R=%0d T=%0d dT=%0d", reg_mode, $signed(T_in), $signed(dT_in)));
        end
      end
    end

    // Σw~0 edge: extremes (expect G=0)
    reg_mode = 1'b1; T_in=-128; dT_in=127; compute_and_check_expected("Edge sum_w~0");

    // --- Block 2: DT_MODE=0, random MAE over ≥1000 samples (REQ-310) ---
    N = 1000; mae_acc = 0;
    reg_mode = 1'b1; // any mode, MAE liczymy względem referencji
    for (i=0; i<N; i++) begin
      T_in  = $urandom_range(-128,127);
      dT_in = $urandom_range(-128,127);
      // compute expected & check
      pulse_start();
      // (reuse compute_and_check_expected for exact check AND to keep logs compact)
      // Do an inline variant to accumulate MAE without duplicate pulses:
      // -> recompute expected here to avoid double starts
      // Fuzzify
      
      muTn=ref_mu(T_in,T_neg_a,T_neg_b,T_neg_c,T_neg_d);
      muTz=ref_mu(T_in,T_zero_a,T_zero_b,T_zero_c,T_zero_d);
      muTp=ref_mu(T_in,T_pos_a, T_pos_b, T_pos_c, T_pos_d);
      muDn=ref_mu(dT_in,dT_neg_a,dT_neg_b,dT_neg_c,dT_neg_d);
      muDz=ref_mu(dT_in,dT_zero_a,dT_zero_b,dT_zero_c,dT_zero_d);
      muDp=ref_mu(dT_in,dT_pos_a, dT_pos_b, dT_pos_c, dT_pos_d);
      w00=q15_min(muTn,muDn); w01=q15_min(muTn,muDz); w02=q15_min(muTn,muDp);
      w10=q15_min(muTz,muDn); w11=q15_min(muTz,muDz); w12=q15_min(muTz,muDp);
      w20=q15_min(muTp,muDn); w21=q15_min(muTp,muDz); w22=q15_min(muTp,muDp);
      sumw=20'd0; sumwg=20'd0;
      sumw += w00; sumwg += w_mul_g_q15(w00,G00);
      sumw += w02; sumwg += w_mul_g_q15(w02,G02);
      sumw += w20; sumwg += w_mul_g_q15(w20,G20);
      sumw += w22; sumwg += w_mul_g_q15(w22,G22);
      if (reg_mode) begin
        sumw += w01; sumwg += w_mul_g_q15(w01,G01);
        sumw += w10; sumwg += w_mul_g_q15(w10,G10);
        sumw += w11; sumwg += w_mul_g_q15(w11,G11);
        sumw += w12; sumwg += w_mul_g_q15(w12,G12);
        sumw += w21; sumwg += w_mul_g_q15(w21,G21);
      end
      if (sumw  > 20'd32767) sumw  = 20'd32767;
      if (sumwg > 20'd32767) sumwg = 20'd32767;
      Gexp = ref_defuzz(sumw[15:0], sumwg[15:0]);

      wait_valid_count_cycles(latR); check_valid_one_shot(); @(posedge clk);
      diff = (G_out > Gexp) ? (G_out - Gexp) : (Gexp - G_out);
      mae_acc += diff;
    end
    mae = mae_acc / N; // in % points (0..100)
    if (verbose) $display("INFO: [REQ-310] MAE over %0d samples = %0d (%%)", N, mae);
    assert (mae <= 1) else $error("[REQ-310] MAE=%0d%% > 1%%", mae);

    // --- Block 3: DT_MODE=1, estimator scenarios (REQ-060/061/062 + 230) ---
    dt_mode = 1'b1; reg_mode = 1'b1;

    // INIT → no spike
    pulse_init();
    pulse_start(); wait_valid_count_cycles(lat1); assert (lat1 <= 10) else $error("[REQ-230] latency after INIT=%0d", lat1);
    check_valid_one_shot(); @(posedge clk); assert (G_out == 8'd0) else $error("[REQ-062] G_out not zero right after INIT/start");

    // Steady at T=0 (2 runs): output should remain bounded and not spike
    T_in = 0;
    repeat (2) begin
      pulse_start(); wait_valid_count_cycles(latS); assert (latS <= 10);
      check_valid_one_shot(); @(posedge clk);
      assert (G_out <= 8'd100) else $error("[REQ-210] bound");
    end

    // Ramp up: T from 0 to +40 step 2
    for (i=0; i<20; i++) begin
      T_in = i*2;
      pulse_start(); wait_valid_count_cycles(latU); assert (latU <= 10);
      check_valid_one_shot(); @(posedge clk);
      assert (G_out <= 8'd100);
    end

    // Ramp down back to 0
    for (i=20; i>=0; i--) begin
      T_in = i*2;
      pulse_start(); wait_valid_count_cycles(latD); assert (latD <= 10);
      check_valid_one_shot(); @(posedge clk);
      assert (G_out <= 8'd100);
    end

    // Random walk of T (length 100)
    T_in = 0;
    for (i=0; i<100; i++) begin
      step = $urandom_range(-5,5);
      nxt  = $signed(T_in) + step;
      if (nxt > 127) nxt = 127; if (nxt < -128) nxt = -128;
      T_in = nxt[7:0];
      pulse_start(); wait_valid_count_cycles(latRW); assert (latRW <= 10);
      check_valid_one_shot(); @(posedge clk);
      assert (G_out <= 8'd100);
    end

    $display("[REQ-010][REQ-020][REQ-030][REQ-040][REQ-050][REQ-060][REQ-061][REQ-062][REQ-210][REQ-230][REQ-320][REQ-310] system TB finished");
    $finish;
  end
endmodule
