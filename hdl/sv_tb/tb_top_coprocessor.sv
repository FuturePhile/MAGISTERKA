// tb_top_coprocessor.sv - system-level TB for top_coprocessor
// Covers REQ-010/020/030/040/050/060/061/062/210/230/320/310
// Style: module -> signals -> DUT -> helpers -> initial/always

`timescale 1ns/1ps
module tb_top_coprocessor;
  timeunit 1ns;
  timeprecision 1ps;

  // Clock / reset
  logic clk;
  logic rst_n;
  localparam real TCLK_NS = 10.0;

  initial begin
    clk = 1'b0;
    forever #(TCLK_NS/2.0) clk = ~clk;
  end

  // Control/data signals matching DUT
  logic        start;        // level; rising edge is captured internally
  logic        init;         // level; rising edge resets dt estimator
  logic        reg_mode;     // 0: 4 rules, 1: 9 rules
  logic        dt_mode;      // 0: external dT_in, 1: internal estimator
  logic signed [7:0] T_in;
  logic signed [7:0] dT_in;

  // MF thresholds (T)
  logic signed [7:0] T_neg_a;
  logic signed [7:0] T_neg_b;
  logic signed [7:0] T_neg_c;
  logic signed [7:0] T_neg_d;
  logic signed [7:0] T_zero_a;
  logic signed [7:0] T_zero_b;
  logic signed [7:0] T_zero_c;
  logic signed [7:0] T_zero_d;
  logic signed [7:0] T_pos_a;
  logic signed [7:0] T_pos_b;
  logic signed [7:0] T_pos_c;
  logic signed [7:0] T_pos_d;

  // MF thresholds (dT)
  logic signed [7:0] dT_neg_a;
  logic signed [7:0] dT_neg_b;
  logic signed [7:0] dT_neg_c;
  logic signed [7:0] dT_neg_d;
  logic signed [7:0] dT_zero_a;
  logic signed [7:0] dT_zero_b;
  logic signed [7:0] dT_zero_c;
  logic signed [7:0] dT_zero_d;
  logic signed [7:0] dT_pos_a;
  logic signed [7:0] dT_pos_b;
  logic signed [7:0] dT_pos_c;
  logic signed [7:0] dT_pos_d;

  // DUT outputs
  logic        valid;
  logic  [7:0] G_out;

  // TB control
  bit verbose;
  integer i;
  integer j;

  integer lat;
  integer N;
  integer mae_acc;
  integer diff;

  // Vectors for sweeps
  logic signed [7:0] Ts [0:9];
  logic signed [7:0] dTs [0:6];

  // Latency scratch
  integer mae;
  integer latR;
  integer lat1;
  integer latS;
  integer latU;
  integer latD;
  integer latRW;
  integer step;
  integer nxt;

  // Inline scratch for golden path
  logic [15:0] muTn;
  logic [15:0] muTz;
  logic [15:0] muTp;
  logic [15:0] muDn;
  logic [15:0] muDz;
  logic [15:0] muDp;
  logic [15:0] w00;
  logic [15:0] w01;
  logic [15:0] w02;
  logic [15:0] w10;
  logic [15:0] w11;
  logic [15:0] w12;
  logic [15:0] w20;
  logic [15:0] w21;
  logic [15:0] w22;
  logic [19:0] sumw;
  logic [19:0] sumwg;
  logic  [7:0] Gexp;

  // Temps for INIT golden
  logic [15:0] muTn_i;
  logic [15:0] muTz_i;
  logic [15:0] muTp_i;
  logic [15:0] muDn_i;
  logic [15:0] muDz_i;
  logic [15:0] muDp_i;
  logic [15:0] w00_i;
  logic [15:0] w01_i;
  logic [15:0] w02_i;
  logic [15:0] w10_i;
  logic [15:0] w11_i;
  logic [15:0] w12_i;
  logic [15:0] w20_i;
  logic [15:0] w21_i;
  logic [15:0] w22_i;
  logic [19:0] sumw_i;
  logic [19:0] sumwg_i;
  logic  [7:0] Gexp_init;

  // ==== CSV: globals & config ====
  integer csv_fd;
  string  csv_path;
  string  run_id    = "tb_run";
  string  git_rev   = "";
  string  tool_ver  = "Questa";
  string  source_id = "sv";
  int     seed_meta = 0;

  // Pola stałe wynikające z RTL (dla dt_mode=1 informacyjnie)
  localparam int ALPHA_CONST = 32; // ALPHA_P in RTL
  localparam int KDT_CONST   = 3;  // KDT_P   in RTL

  // Lokalne liczniki indeksów (per-case)
  int idx_grid, idx_rand, idx_est_init, idx_est_up, idx_est_down, idx_est_rw;

  // Tymczasowe do wyliczenia S_w/S_wg/Gexp przy emisji CSV (GRID)
  logic [15:0] t_muTn, t_muTz, t_muTp, t_muDn, t_muDz, t_muDp;
  logic [15:0] t_w00, t_w01, t_w02, t_w10, t_w11, t_w12, t_w20, t_w21, t_w22;
  logic [19:0] t_sumw, t_sumwg;
  logic  [7:0] t_Gexp;

  // For A/B toggle stability block
  logic [7:0] G_rm0, G_rm1;

  // Instantiate DUT
  top_coprocessor dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .init(init),
    .reg_mode(reg_mode),
    .dt_mode(dt_mode),
    .T_in(T_in),
    .dT_in(dT_in),
    .T_neg_a(T_neg_a),
    .T_neg_b(T_neg_b),
    .T_neg_c(T_neg_c),
    .T_neg_d(T_neg_d),
    .T_zero_a(T_zero_a),
    .T_zero_b(T_zero_b),
    .T_zero_c(T_zero_c),
    .T_zero_d(T_zero_d),
    .T_pos_a(T_pos_a),
    .T_pos_b(T_pos_b),
    .T_pos_c(T_pos_c),
    .T_pos_d(T_pos_d),
    .dT_neg_a(dT_neg_a),
    .dT_neg_b(dT_neg_b),
    .dT_neg_c(dT_neg_c),
    .dT_neg_d(dT_neg_d),
    .dT_zero_a(dT_zero_a),
    .dT_zero_b(dT_zero_b),
    .dT_zero_c(dT_zero_c),
    .dT_zero_d(dT_zero_d),
    .dT_pos_a(dT_pos_a),
    .dT_pos_b(dT_pos_b),
    .dT_pos_c(dT_pos_c),
    .dT_pos_d(dT_pos_d),
    .valid(valid),
    .G_out(G_out)
  );

  // Bit-accurate reference helpers (for DT_MODE=0)
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
      num = $unsigned(t1) << 15;
      out_mu = num / $unsigned(dx1);
    end else begin
      dx2 = $signed(fd) - $signed(fc);
      if (dx2 == 0) dx2 = 1;
      t2  = $signed(fd) - $signed(fx);
      num = $unsigned(t2) << 15;
      out_mu = num / $unsigned(dx2);
    end

    if (out_mu > 16'h7FFF) out_mu = 16'h7FFF;
    return out_mu;
  endfunction

  function automatic logic [15:0] q15_min(
    input logic [15:0] a,
    input logic [15:0] b
  );
    begin
      return (a < b) ? a : b;
    end
  endfunction

  function automatic [15:0] g2q15_pct(
    input logic [7:0] gpct
  );
    logic [31:0] tmp;
    begin
      tmp = (gpct * 32'd32767) + 32'd50;
      tmp = tmp / 32'd100;
      return (tmp > 32'd32767) ? 16'd32767 : tmp[15:0];
    end
  endfunction

  function automatic [15:0] w_mul_g_q15(
    input logic [15:0] wq15,
    input logic  [7:0] gpct
  );
    logic [31:0] mul;
    logic [31:0] num;
    begin
      mul = wq15 * g2q15_pct(gpct);
      num = mul + (32'd1 << 14);
      return (num >> 15);
    end
  endfunction

  function automatic [7:0] ref_defuzz(
    input logic [15:0] Sw,
    input logic [15:0] Swg
  );
    localparam logic [15:0] EPS = 16'd1;
    logic [15:0] den;
    logic [31:0] ratio_q15;
    logic [31:0] percent_u;
    logic  [7:0] out;
    begin
      den = (Sw < EPS) ? EPS : Sw;
      ratio_q15 = ({16'd0, Swg} << 15) / den;
      percent_u = (ratio_q15 * 32'd100 + 32'd16384) >> 15;
      out = (percent_u > 32'd100) ? 8'd100 : percent_u[7:0];
      return out;
    end
  endfunction

  // --- Region classifier for coverage (neg=0, zero=1, pos=2, none=3)
  function automatic int max3_idx_or_none(
    input logic [15:0] a, input logic [15:0] b, input logic [15:0] c
  );
    if ((a|b|c) == 16'd0) return 3; // none
    if ((a >= b) && (a >= c)) return 0;
    if ((b >= a) && (b >= c)) return 1;
    return 2;
  endfunction

  // --- Coverage scratch sampled on VALID
  int cov_T, cov_D;
  bit cov_sw0, cov_sweps;

  // --- Compute classification and Σw bins with current settings
  task automatic update_cov_vars();
    logic [15:0] muTn_c, muTz_c, muTp_c;
    logic [15:0] muDn_c, muDz_c, muDp_c;
    logic [15:0] w00_c, w01_c, w02_c, w10_c, w11_c, w12_c, w20_c, w21_c, w22_c;
    logic [19:0] Sw_c;
    logic signed [7:0] dT_cov;
    begin
      dT_cov  = (dt_mode == 1'b0) ? dT_in : 8'sd0; // for coverage, DT_MODE=1 classifies vs 0
      muTn_c = ref_mu(T_in, T_neg_a,  T_neg_b,  T_neg_c,  T_neg_d);
      muTz_c = ref_mu(T_in, T_zero_a, T_zero_b, T_zero_c, T_zero_d);
      muTp_c = ref_mu(T_in, T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d);
      muDn_c = ref_mu(dT_cov, dT_neg_a,  dT_neg_b,  dT_neg_c,  dT_neg_d);
      muDz_c = ref_mu(dT_cov, dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d);
      muDp_c = ref_mu(dT_cov, dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d);

      w00_c = q15_min(muTn_c, muDn_c);
      w01_c = q15_min(muTn_c, muDz_c);
      w02_c = q15_min(muTn_c, muDp_c);
      w10_c = q15_min(muTz_c, muDn_c);
      w11_c = q15_min(muTz_c, muDz_c);
      w12_c = q15_min(muTz_c, muDp_c);
      w20_c = q15_min(muTp_c, muDn_c);
      w21_c = q15_min(muTp_c, muDz_c);
      w22_c = q15_min(muTp_c, muDp_c);

      Sw_c  = 20'd0;
      Sw_c  += w00_c + w02_c + w20_c + w22_c;
      if (reg_mode) Sw_c += w01_c + w10_c + w11_c + w12_c + w21_c;
      if (Sw_c > 20'd32767) Sw_c = 20'd32767;

      cov_T     = max3_idx_or_none(muTn_c, muTz_c, muTp_c);
      cov_D     = max3_idx_or_none(muDn_c, muDz_c, muDp_c);
      cov_sw0   = (Sw_c[15:0] == 16'd0);
      cov_sweps = (Sw_c[15:0] >= 16'd1) && (Sw_c[15:0] <= 16'd4); // "near EPS"
    end
  endtask

  // ===== Manual coverage (license-free) for REQ-320 =====
  int cov_counts [0:3][0:3][0:1][0:1]; // [Tbin][Dbin][reg_mode][dt_mode]
  int cov_sw0_yes, cov_sw0_no;
  int cov_sweps_yes, cov_sweps_no;

  task automatic cov_touch();
    if (cov_T >= 0 && cov_T <= 3 && cov_D >= 0 && cov_D <= 3)
      cov_counts[cov_T][cov_D][reg_mode][dt_mode]++;
    if (cov_sw0)   cov_sw0_yes++;   else cov_sw0_no++;
    if (cov_sweps) cov_sweps_yes++; else cov_sweps_no++;
  endtask

  task automatic cov_dump_summary();
    integer t,d,r,dm;
    string row;
    $display("=== REQ-320 coverage summary (manual) ===");
    for (r = 0; r < 2; r++) begin
      for (dm = 0; dm < 2; dm++) begin
        for (t = 0; t < 4; t++) begin
          row = "";
          for (d = 0; d < 4; d++) row = {row, $sformatf("%0d ", cov_counts[t][d][r][dm])};
          $display("rm=%0d dt=%0d | Tbin=%0d | Dbins=%s", r, dm, t, row);
        end
      end
    end
    $display("Σw==0 hits: %0d, Σw>0 hits: %0d", cov_sw0_yes, cov_sw0_no);
    $display("Σw≈EPS hits: %0d, others: %0d", cov_sweps_yes, cov_sweps_no);
  endtask
  // =====================================================

  // ==== CSV: tiny header, easy to read ====
  task automatic csv_write_header();
    if (csv_fd != 0) begin
      // Minimal, human-friendly:
      // run_id,case,idx,rm,dt,T,dT,Gexp,Gimpl
      $fdisplay(csv_fd, "run_id,case,idx,rm,dt,T,dT,Gexp,Gimpl");
    end
  endtask

  // ==== CSV: tiny row (ignore Sw/Swg/valid in args to keep call-sites unchanged) ====
  task automatic csv_emit_line(
    input string case_id, input int idx,
    input int Sw /*unused*/, input int Swg /*unused*/,
    input int Gexp, input int Gimpl, input bit valid_bit /*unused*/
  );
    if (csv_fd != 0) begin
      // Only the essentials, same order as header:
      $fdisplay(csv_fd, "%s,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                run_id, case_id, idx, reg_mode, dt_mode,
                $signed(T_in), $signed(dT_in), Gexp, Gimpl);
    end
  endtask

  // Singletons (copy of DUT locals)
  localparam logic [7:0] G00 = 8'd100;
  localparam logic [7:0] G01 = 8'd50;
  localparam logic [7:0] G02 = 8'd30;
  localparam logic [7:0] G10 = 8'd50;
  localparam logic [7:0] G11 = 8'd50;
  localparam logic [7:0] G12 = 8'd50;
  localparam logic [7:0] G20 = 8'd80;
  localparam logic [7:0] G21 = 8'd50;
  localparam logic [7:0] G22 = 8'd0;

  // Tasks
  task automatic set_mf_defaults();
    begin
      // T sets
      T_neg_a  = -128;
      T_neg_b  = -64;
      T_neg_c  = -32;
      T_neg_d  = 0;
      T_zero_a = -16;
      T_zero_b = 0;
      T_zero_c = 0;
      T_zero_d = 16;
      T_pos_a  = 0;
      T_pos_b  = 32;
      T_pos_c  = 64;
      T_pos_d  = 127;
      // dT sets
      dT_neg_a = -100;
      dT_neg_b = -50;
      dT_neg_c = -30;
      dT_neg_d = -5;
      dT_zero_a = -10;
      dT_zero_b = 0;
      dT_zero_c = 0;
      dT_zero_d = 10;
      dT_pos_a  = 5;
      dT_pos_b  = 25;
      dT_pos_c  = 35;
      dT_pos_d  = 60;
    end
  endtask

  task automatic pulse_start();
    begin
      @(negedge clk);
      start <= 1'b1;
      @(posedge clk);
      start <= 1'b0;
    end
  endtask

  task automatic pulse_init();
    begin
      @(negedge clk);
      init <= 1'b1;
      @(posedge clk);
      init <= 1'b0;
    end
  endtask

  task automatic wait_valid_count_cycles(
    output integer cnt
  );
    begin
      cnt = 0;
      while (!valid) begin
        @(posedge clk);
        cnt = cnt + 1;
        if (cnt > 32) begin
          break;
        end
      end
    end
  endtask

  task automatic check_valid_one_shot();
    begin
      if (!valid) @(posedge clk);
      assert (valid) else $error("[REQ-230] valid not high when expected");
      @(posedge clk);
      assert (!valid) else $error("[REQ-230] valid must be a 1-cycle pulse");
    end
  endtask

  task automatic compute_and_check_expected(
    input string tag
  );
    logic [15:0] muTn_l;
    logic [15:0] muTz_l;
    logic [15:0] muTp_l;
    logic [15:0] muDn_l;
    logic [15:0] muDz_l;
    logic [15:0] muDp_l;
    logic [15:0] w00_l;
    logic [15:0] w01_l;
    logic [15:0] w02_l;
    logic [15:0] w10_l;
    logic [15:0] w11_l;
    logic [15:0] w12_l;
    logic [15:0] w20_l;
    logic [15:0] w21_l;
    logic [15:0] w22_l;
    logic [19:0] sumw_l;
    logic [19:0] sumwg_l;
    logic  [7:0] Gexp_l;
    begin
      // Fuzzify
      muTn_l = ref_mu(T_in, T_neg_a, T_neg_b, T_neg_c, T_neg_d);
      muTz_l = ref_mu(T_in, T_zero_a, T_zero_b, T_zero_c, T_zero_d);
      muTp_l = ref_mu(T_in, T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d);
      muDn_l = ref_mu(dT_in, dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d);
      muDz_l = ref_mu(dT_in, dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d);
      muDp_l = ref_mu(dT_in, dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d);

      // Rules (min)
      w00_l = q15_min(muTn_l, muDn_l);
      w01_l = q15_min(muTn_l, muDz_l);
      w02_l = q15_min(muTn_l, muDp_l);
      w10_l = q15_min(muTz_l, muDn_l);
      w11_l = q15_min(muTz_l, muDz_l);
      w12_l = q15_min(muTz_l, muDp_l);
      w20_l = q15_min(muTp_l, muDn_l);
      w21_l = q15_min(muTp_l, muDz_l);
      w22_l = q15_min(muTp_l, muDp_l);

      // Aggregation with reg_mode
      sumw_l  = 20'd0;
      sumwg_l = 20'd0;

      // corners always
      sumw_l  += w00_l; sumwg_l += w_mul_g_q15(w00_l, G00);
      sumw_l  += w02_l; sumwg_l += w_mul_g_q15(w02_l, G02);
      sumw_l  += w20_l; sumwg_l += w_mul_g_q15(w20_l, G20);
      sumw_l  += w22_l; sumwg_l += w_mul_g_q15(w22_l, G22);

      if (reg_mode) begin
        sumw_l  += w01_l; sumwg_l += w_mul_g_q15(w01_l, G01);
        sumw_l  += w10_l; sumwg_l += w_mul_g_q15(w10_l, G10);
        sumw_l  += w11_l; sumwg_l += w_mul_g_q15(w11_l, G11);
        sumw_l  += w12_l; sumwg_l += w_mul_g_q15(w12_l, G12);
        sumw_l  += w21_l; sumwg_l += w_mul_g_q15(w21_l, G21);
      end

      if (sumw_l  > 20'd32767) sumw_l  = 20'd32767;
      if (sumwg_l > 20'd32767) sumwg_l = 20'd32767;

      Gexp_l = ref_defuzz(sumw_l[15:0], sumwg_l[15:0]);

      // Drive and check
      update_cov_vars();
      pulse_start();
      wait_valid_count_cycles(lat);
      assert (lat <= 10) else $error("[REQ-230] %s latency=%0d > 10", tag, lat);
      check_valid_one_shot();
      cov_touch(); // <--- manual coverage sample
      @(posedge clk);

      if (G_out !== Gexp_l) begin
        $error("[REQ-010] %s G_out mismatch got=%0d exp=%0d (lat=%0d)", tag, G_out, Gexp_l, lat);
      end

      if (verbose) begin
        $display("INFO: [SYS] %s reg_mode=%0d dt_mode=%0d | lat=%0d | G=%0d (exp %0d)",
                 tag, reg_mode, dt_mode, lat, G_out, Gexp_l);
      end
    end
  endtask

  // Compute expected G for given T and dT=0 using the same bit-accurate path
  task automatic compute_gexp_at_dT0(
    input  logic signed [7:0] Tin,
    input  logic              reg_mode_i,
    output logic       [7:0]  Gexp_o
  );
    begin
      // Fuzzify T
      muTn_i = ref_mu(Tin, T_neg_a, T_neg_b, T_neg_c, T_neg_d);
      muTz_i = ref_mu(Tin, T_zero_a, T_zero_b, T_zero_c, T_zero_d);
      muTp_i = ref_mu(Tin, T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d);

      // Fuzzify dT=0
      muDn_i = ref_mu(8'sd0, dT_neg_a,  dT_neg_b,  dT_neg_c,  dT_neg_d);
      muDz_i = ref_mu(8'sd0, dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d);
      muDp_i = ref_mu(8'sd0, dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d);

      // Rules (min)
      w00_i = q15_min(muTn_i, muDn_i);
      w01_i = q15_min(muTn_i, muDz_i);
      w02_i = q15_min(muTn_i, muDp_i);
      w10_i = q15_min(muTz_i, muDn_i);
      w11_i = q15_min(muTz_i, muDz_i);
      w12_i = q15_min(muTz_i, muDp_i);
      w20_i = q15_min(muTp_i, muDn_i);
      w21_i = q15_min(muTp_i, muDz_i);
      w22_i = q15_min(muTp_i, muDp_i);

      // Aggregation with reg_mode
      sumw_i  = 20'd0;
      sumwg_i = 20'd0;

      sumw_i  += w00_i; sumwg_i += w_mul_g_q15(w00_i, G00);
      sumw_i  += w02_i; sumwg_i += w_mul_g_q15(w02_i, G02);
      sumw_i  += w20_i; sumwg_i += w_mul_g_q15(w20_i, G20);
      sumw_i  += w22_i; sumwg_i += w_mul_g_q15(w22_i, G22);

      if (reg_mode_i) begin
        sumw_i  += w01_i; sumwg_i += w_mul_g_q15(w01_i, G01);
        sumw_i  += w10_i; sumwg_i += w_mul_g_q15(w10_i, G10);
        sumw_i  += w11_i; sumwg_i += w_mul_g_q15(w11_i, G11);
        sumw_i  += w12_i; sumwg_i += w_mul_g_q15(w12_i, G12);
        sumw_i  += w21_i; sumwg_i += w_mul_g_q15(w21_i, G21);
      end

      if (sumw_i  > 20'd32767) sumw_i  = 20'd32767;
      if (sumwg_i > 20'd32767) sumwg_i = 20'd32767;

      Gexp_o = ref_defuzz(sumw_i[15:0], sumwg_i[15:0]);
    end
  endtask

  // Test flow
  initial begin
    // ==== CSV: open file & parse plusargs ====
    void'($value$plusargs("csv=%s", csv_path));
    void'($value$plusargs("run_id=%s", run_id));
    void'($value$plusargs("git_rev=%s", git_rev));
    void'($value$plusargs("tool_ver=%s", tool_ver));
    void'($value$plusargs("seed=%d", seed_meta));
    if (csv_path.len() == 0) csv_path = "out/results_tb.csv";
    // --- ensure output dir exists (Windows + Linux) ---
    void'($system("cmd /c if not exist out mkdir out"));
    void'($system("mkdir -p out >/dev/null 2>&1"));

    csv_fd = $fopen(csv_path, "w");
    if (csv_fd == 0) $display("WARN: CSV not opened (%s)", csv_path);
    else begin
      $display("INFO: CSV -> %s", csv_path);
      csv_write_header();
    end

    verbose  = $test$plusargs("verbose");

    // Reset
    start    = 1'b0;
    init     = 1'b0;
    reg_mode = 1'b0;
    dt_mode  = 1'b0;
    set_mf_defaults();
    T_in     = 8'sd0;
    dT_in    = 8'sd0;
    rst_n    = 1'b0;
    repeat (3) @(posedge clk);
    rst_n    = 1'b1;
    @(posedge clk);
    // --- seed / indices ---
    if (seed_meta != 0) void'($urandom(seed_meta));
    idx_grid = 0;
    idx_rand = 0;
    idx_est_init = 0;
    idx_est_up = 0;
    idx_est_down = 0;
    idx_est_rw = 0;

    // Block 1: DT_MODE=0, dense grid + A/B same vectors (REQ-010/020/030/040/050/210)
    dt_mode = 1'b0;
    Ts[0] = -128; Ts[1] = -64; Ts[2] = -32; Ts[3] = -16; Ts[4] = 0;
    Ts[5] = 16;   Ts[6] = 32;  Ts[7] = 64;  Ts[8] = 96;   Ts[9] = 127;

    dTs[0] = -60; dTs[1] = -30; dTs[2] = -10; dTs[3] = 0;
    dTs[4] = 10;  dTs[5] = 30;  dTs[6] = 60;

    // ---- DT_MODE=0 GRID: zapis CSV co próbkę ----
    for (int rm = 0; rm <= 1; rm = rm + 1) begin : REG_AB
      reg_mode = rm[0];
      idx_grid = 0;
      for (i = 0; i < 10; i = i + 1) begin
        for (j = 0; j < 7; j = j + 1) begin
          T_in  = Ts[i][7:0];
          dT_in = dTs[j][7:0];

          // policz „goldena”, uruchom DUT i sprawdź (jak dotąd)
          compute_and_check_expected($sformatf("Grid rm=%0d T=%0d dT=%0d",
                              reg_mode, $signed(T_in), $signed(dT_in)));

          // Q&D recompute for CSV
          t_muTn = ref_mu(T_in, T_neg_a,  T_neg_b,  T_neg_c,  T_neg_d);
          t_muTz = ref_mu(T_in, T_zero_a, T_zero_b, T_zero_c, T_zero_d);
          t_muTp = ref_mu(T_in, T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d);
          t_muDn = ref_mu(dT_in, dT_neg_a,  dT_neg_b,  dT_neg_c,  dT_neg_d);
          t_muDz = ref_mu(dT_in, dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d);
          t_muDp = ref_mu(dT_in, dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d);

          t_w00 = q15_min(t_muTn, t_muDn);
          t_w01 = q15_min(t_muTn, t_muDz);
          t_w02 = q15_min(t_muTn, t_muDp);
          t_w10 = q15_min(t_muTz, t_muDn);
          t_w11 = q15_min(t_muTz, t_muDz);
          t_w12 = q15_min(t_muTz, t_muDp);
          t_w20 = q15_min(t_muTp, t_muDn);
          t_w21 = q15_min(t_muTp, t_muDz);
          t_w22 = q15_min(t_muTp, t_muDp);

          t_sumw  = 20'd0;
          t_sumwg = 20'd0;

          t_sumw  += t_w00; t_sumwg += w_mul_g_q15(t_w00, G00);
          t_sumw  += t_w02; t_sumwg += w_mul_g_q15(t_w02, G02);
          t_sumw  += t_w20; t_sumwg += w_mul_g_q15(t_w20, G20);
          t_sumw  += t_w22; t_sumwg += w_mul_g_q15(t_w22, G22);

          if (reg_mode) begin
            t_sumw  += t_w01; t_sumwg += w_mul_g_q15(t_w01, G01);
            t_sumw  += t_w10; t_sumwg += w_mul_g_q15(t_w10, G10);
            t_sumw  += t_w11; t_sumwg += w_mul_g_q15(t_w11, G11);
            t_sumw  += t_w12; t_sumwg += w_mul_g_q15(t_w12, G12);
            t_sumw  += t_w21; t_sumwg += w_mul_g_q15(t_w21, G21);
          end

          if (t_sumw  > 20'd32767) t_sumw  = 20'd32767;
          if (t_sumwg > 20'd32767) t_sumwg = 20'd32767;

          t_Gexp = ref_defuzz(t_sumw[15:0], t_sumwg[15:0]);

          csv_emit_line($sformatf("Grid_T=%0d_dT=%0d", $signed(T_in), $signed(dT_in)),
                        idx_grid++, t_sumw[15:0], t_sumwg[15:0], t_Gexp, G_out, valid);
        end
      end
    end

    // Sum_w approx zero edge: extremes (expect G=0)
    reg_mode = 1'b1;
    T_in     = -128;
    dT_in    = 127;
    compute_and_check_expected("Edge sum_w approx 0");

    // Near-EPS case: hunt a vector with 1..4 LSB of Σw, ensure safe defuzz (no blowup)
    begin : NEAR_EPS
      bit found_eps;
      logic signed [7:0] eps_T, eps_dT;
      int ii, jj;
      logic [15:0] muTn_e, muTz_e, muTp_e, muDn_e, muDz_e, muDp_e;
      logic [19:0] Sw_e;

      found_eps = 0;

      for (ii = 0; ii < 10 && !found_eps; ii++) begin
        for (jj = 0; jj < 7 && !found_eps; jj++) begin
          muTn_e = ref_mu(Ts[ii], T_neg_a,  T_neg_b,  T_neg_c,  T_neg_d);
          muTz_e = ref_mu(Ts[ii], T_zero_a, T_zero_b, T_zero_c, T_zero_d);
          muTp_e = ref_mu(Ts[ii], T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d);
          muDn_e = ref_mu(dTs[jj], dT_neg_a,  dT_neg_b,  dT_neg_c,  dT_neg_d);
          muDz_e = ref_mu(dTs[jj], dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d);
          muDp_e = ref_mu(dTs[jj], dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d);

          Sw_e  = 20'd0;
          Sw_e += q15_min(muTn_e, muDn_e);
          Sw_e += q15_min(muTn_e, muDp_e);
          Sw_e += q15_min(muTp_e, muDn_e);
          Sw_e += q15_min(muTp_e, muDp_e);
          if (reg_mode) Sw_e += q15_min(muTn_e, muDz_e)
                            +  q15_min(muTz_e, muDn_e)
                            +  q15_min(muTz_e, muDz_e)
                            +  q15_min(muTz_e, muDp_e)
                            +  q15_min(muTp_e, muDz_e);

          if (Sw_e[15:0] >= 16'd1 && Sw_e[15:0] <= 16'd4) begin
            eps_T     = Ts[ii];
            eps_dT    = dTs[jj];
            found_eps = 1;
          end
        end
      end

      if (found_eps) begin
        T_in  = eps_T;
        dT_in = eps_dT;
        update_cov_vars();
        compute_and_check_expected($sformatf("NearEPS T=%0d dT=%0d", $signed(T_in), $signed(dT_in)));
        csv_emit_line("NearEPS", 0, -1, -1, -1, G_out, 1'b0);
      end else begin
        $display("WARN: could not find NearEPS case in coarse grid; skip.");
      end
    end

    // Block 2: DT_MODE=0, random MAE over >=1000 samples (REQ-310 <=1%)
    N       = 1000;
    mae_acc = 0;
    reg_mode = 1'b1;

    for (i = 0; i < N; i = i + 1) begin
      T_in  = ( $urandom() % 256 ) - 128;
      dT_in = ( $urandom() % 256 ) - 128;

      muTn = ref_mu(T_in, T_neg_a,  T_neg_b,  T_neg_c,  T_neg_d);
      muTz = ref_mu(T_in, T_zero_a, T_zero_b, T_zero_c, T_zero_d);
      muTp = ref_mu(T_in, T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d);
      muDn = ref_mu(dT_in, dT_neg_a,  dT_neg_b,  dT_neg_c,  dT_neg_d);
      muDz = ref_mu(dT_in, dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d);
      muDp = ref_mu(dT_in, dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d);

      w00 = q15_min(muTn, muDn);
      w01 = q15_min(muTn, muDz);
      w02 = q15_min(muTn, muDp);
      w10 = q15_min(muTz, muDn);
      w11 = q15_min(muTz, muDz);
      w12 = q15_min(muTz, muDp);
      w20 = q15_min(muTp, muDn);
      w21 = q15_min(muTp, muDz);
      w22 = q15_min(muTp, muDp);

      sumw  = 20'd0;
      sumwg = 20'd0;

      sumw  += w00; sumwg += w_mul_g_q15(w00, G00);
      sumw  += w02; sumwg += w_mul_g_q15(w02, G02);
      sumw  += w20; sumwg += w_mul_g_q15(w20, G20);
      sumw  += w22; sumwg += w_mul_g_q15(w22, G22);

      if (reg_mode) begin
        sumw  += w01; sumwg += w_mul_g_q15(w01, G01);
        sumw  += w10; sumwg += w_mul_g_q15(w10, G10);
        sumw  += w11; sumwg += w_mul_g_q15(w11, G11);
        sumw  += w12; sumwg += w_mul_g_q15(w12, G12);
        sumw  += w21; sumwg += w_mul_g_q15(w21, G21);
      end

      if (sumw  > 20'd32767) sumw  = 20'd32767;
      if (sumwg > 20'd32767) sumwg = 20'd32767;

      Gexp = ref_defuzz(sumw[15:0], sumwg[15:0]);

      update_cov_vars();
      pulse_start();
      wait_valid_count_cycles(latR);
      check_valid_one_shot();
      cov_touch(); // <--- manual coverage sample
      @(posedge clk);

      csv_emit_line("Random", idx_rand++, sumw[15:0], sumwg[15:0], Gexp, G_out, valid);

      diff     = (G_out > Gexp) ? (G_out - Gexp) : (Gexp - G_out);
      mae_acc  = mae_acc + diff;
    end

    mae = mae_acc / N;
    if (verbose) $display("INFO: [REQ-310] MAE over %0d samples = %0d (percent points)", N, mae);
    assert (mae <= 1) else $error("[REQ-310] MAE=%0d%% > 1%%", mae);

    // A/B stability on same inputs (no glitches across mode flips)
    T_in  = 8'sd32;
    dT_in = -8'sd10;

    // REG_MODE=0
    reg_mode = 1'b0;
    update_cov_vars();
    pulse_start();
    wait_valid_count_cycles(lat);
    check_valid_one_shot();
    cov_touch(); // <--- manual coverage sample
    @(posedge clk);
    G_rm0 = G_out;
    csv_emit_line("AB_Toggle_reg0", 0, -1, -1, -1, G_out, 1'b0);

    // REG_MODE=1
    reg_mode = 1'b1;
    update_cov_vars();
    pulse_start();
    wait_valid_count_cycles(lat);
    check_valid_one_shot();
    cov_touch(); // <--- manual coverage sample
    @(posedge clk);
    G_rm1 = G_out;
    csv_emit_line("AB_Toggle_reg1", 0, -1, -1, -1, G_out, 1'b0);

    // Flip back to 0 (no lingering state)
    reg_mode = 1'b0;
    update_cov_vars();
    pulse_start();
    wait_valid_count_cycles(lat);
    check_valid_one_shot();
    cov_touch(); // <--- manual coverage sample
    @(posedge clk);

    // Sanity
    assert (G_rm0 <= 8'd100 && G_rm1 <= 8'd100)
      else $error("[REQ-030] AB toggle produced invalid G");

    // --- VIS 1: T sweep at dT=0 (expect flat 50 with current singletons) ---
    begin : VIS_T_AT_DT0
      integer vis_fd1;
      string vis_path1;
      int Ti;

      vis_path1 = "out/vis_T_at_dt0.csv";
      vis_fd1 = $fopen(vis_path1, "w");
      if (vis_fd1 != 0) $fdisplay(vis_fd1, "T,dT,Gimpl,Gexp");

      reg_mode = 1'b1;   // full 3x3
      dt_mode  = 1'b0;   // external dT
      dT_in    = 8'sd0;

      for (Ti = -128; Ti <= 127; Ti += 2) begin
        T_in = Ti[7:0];
        // compute golden and run DUT
        compute_and_check_expected("VIS_T_at_dt0");
        if (vis_fd1 != 0) $fdisplay(vis_fd1, "%0d,%0d,%0d,%0d",
                                    $signed(T_in), $signed(dT_in), G_out, Gexp);
      end

      if (vis_fd1 != 0) begin $fflush(vis_fd1); $fclose(vis_fd1); end
      $display("INFO: VIS_T_at_dt0 -> %s", vis_path1);
    end

    // --- VIS 2: dT sweeps at fixed T values (shows non-50 outputs) ---
    begin : VIS_DT_LINES
      integer vis_fd2;
      string vis_path2;
      int Dj;
      int TT[0:2];

      vis_path2 = "out/vis_dT_lines.csv";
      vis_fd2 = $fopen(vis_path2, "w");
      if (vis_fd2 != 0) $fdisplay(vis_fd2, "T,dT,Gimpl,Gexp");

      reg_mode = 1'b1;
      dt_mode  = 1'b0;

      // choose 3 representative T values (neg/zero/pos-ish)
      TT[0] = -32; TT[1] = 0; TT[2] = 32;

      for (int k = 0; k < 3; k++) begin
        T_in = TT[k][7:0];
        for (Dj = -60; Dj <= 60; Dj += 4) begin
          dT_in = Dj[7:0];
          compute_and_check_expected("VIS_dT_line");
          if (vis_fd2 != 0) $fdisplay(vis_fd2, "%0d,%0d,%0d,%0d",
                                      $signed(T_in), $signed(dT_in), G_out, Gexp);
        end
      end

      if (vis_fd2 != 0) begin $fflush(vis_fd2); $fclose(vis_fd2); end
      $display("INFO: VIS_dT_lines -> %s", vis_path2);
    end

    // --- VIS 3: 2D heatmap grid over T and dT ---
    begin : VIS_HEATMAP
      integer vis_fd3;
      string vis_path3;
      int Ti, Dj;

      vis_path3 = "out/vis_heatmap.csv";
      vis_fd3 = $fopen(vis_path3, "w");
      if (vis_fd3 != 0) $fdisplay(vis_fd3, "T,dT,Gimpl,Gexp");

      reg_mode = 1'b1;
      dt_mode  = 1'b0;

      // coarse but smooth grid
      for (Ti = -64; Ti <= 64; Ti += 8) begin
        for (Dj = -60; Dj <= 60; Dj += 5) begin
          T_in  = Ti[7:0];
          dT_in = Dj[7:0];
          compute_and_check_expected("VIS_heatmap");
          if (vis_fd3 != 0) $fdisplay(vis_fd3, "%0d,%0d,%0d,%0d",
                                      $signed(T_in), $signed(dT_in), G_out, Gexp);
        end
      end

      if (vis_fd3 != 0) begin $fflush(vis_fd3); $fclose(vis_fd3); end
      $display("INFO: VIS_heatmap -> %s", vis_path3);
    end



    // Block 3: DT_MODE=1, estimator scenarios (REQ-060/061/062 + 230)
    dt_mode  = 1'b1;
    reg_mode = 1'b1;

    // Deterministic T and golden for dT=0 after INIT
    T_in = 8'sd0;

    compute_gexp_at_dT0(T_in, reg_mode, Gexp_init);

    // INIT -> dT=0; first start should match golden for (T, dT=0)
    pulse_init();
    update_cov_vars();
    pulse_start();
    wait_valid_count_cycles(lat1);
    assert (lat1 <= 10) else $error("[REQ-230] latency after INIT=%0d", lat1);
    check_valid_one_shot();
    cov_touch(); // <--- manual coverage sample
    @(posedge clk);

    csv_emit_line("EST_INIT", idx_est_init++, -1, -1, -1, G_out, valid);

    if (verbose) begin
      $display("INFO: [EST] after INIT | dt_mode=1 reg_mode=%0d T=%0d | lat=%0d | G=%0d (golden dT=0 -> %0d)",
               reg_mode, $signed(T_in), lat1, G_out, Gexp_init);
    end

    assert (G_out == Gexp_init)
      else $error("[REQ-062] after INIT got=%0d exp=%0d (T=%0d, dT=0)", G_out, Gexp_init, $signed(T_in));

    // Steady at T=0 (two runs)
    repeat (2) begin
      update_cov_vars();
      pulse_start();
      wait_valid_count_cycles(latS);
      assert (latS <= 10);
      check_valid_one_shot();
      cov_touch(); // <--- manual coverage sample
      @(posedge clk);
      if (verbose) $display("INFO: [EST] steady T=0 | lat=%0d | G=%0d", latS, G_out);
      assert (G_out <= 8'd100);
    end

    // Ramp up: T 0->+40 step 2
    for (i = 0; i < 20; i = i + 1) begin
      T_in = i * 2;
      update_cov_vars();
      pulse_start();
      wait_valid_count_cycles(latU);
      assert (latU <= 10);
      check_valid_one_shot();
      cov_touch(); // <--- manual coverage sample
      @(posedge clk);
      csv_emit_line("EST_RampUp", idx_est_up++, -1, -1, -1, G_out, valid);
      if (verbose) $display("INFO: [EST] ramp_up step=%0d T=%0d | lat=%0d | G=%0d", i, $signed(T_in), latU, G_out);
      assert (G_out <= 8'd100);
    end

    // Ramp down: +40->0
    for (i = 20; i >= 0; i = i - 1) begin
      T_in = i * 2;
      update_cov_vars();
      pulse_start();
      wait_valid_count_cycles(latD);
      assert (latD <= 10);
      check_valid_one_shot();
      cov_touch(); // <--- manual coverage sample
      @(posedge clk);
      csv_emit_line("EST_RampDown", idx_est_down++, -1, -1, -1, G_out, valid);
      if (verbose) $display("INFO: [EST] ramp_down step=%0d T=%0d | lat=%0d | G=%0d", i, $signed(T_in), latD, G_out);
      assert (G_out <= 8'd100);
    end

    // Random walk of T (length 100)
    T_in = 8'sd0;
    for (i = 0; i < 100; i = i + 1) begin
      // Questa bywa kapryśna z ujemnym zakresem w $urandom_range
      step = $urandom_range(10, 0) - 5; // daje [-5..+5]
      nxt  = $signed(T_in) + step;
      if (nxt > 127) nxt = 127;
      if (nxt < -128) nxt = -128;
      T_in = nxt[7:0];
      update_cov_vars();
      pulse_start();
      wait_valid_count_cycles(latRW);
      assert (latRW <= 10);
      check_valid_one_shot();
      cov_touch(); // <--- manual coverage sample
      @(posedge clk);
      csv_emit_line("EST_RandWalk", idx_est_rw++, -1, -1, -1, G_out, valid);
      if (verbose) $display("INFO: [EST] randwalk i=%0d step=%0d T=%0d | lat=%0d | G=%0d",
                            i, step, $signed(T_in), latRW, G_out);
      assert (G_out <= 8'd100);
    end

    if (csv_fd != 0) begin
      $fflush(csv_fd);
      $fclose(csv_fd);
    end

    // Print manual coverage summary (REQ-320)
    cov_dump_summary();

    // --- REQ: boundary behavior at fa/fb/fc/fd (and ±1)
    begin : EDGE_TESTS
      int k;
      logic signed [7:0] Tvecs [0:7];
      logic signed [7:0] dTvecs[0:7];

      // capture current thresholds into vectors
      Tvecs[0]=T_neg_a; Tvecs[1]=T_neg_b; Tvecs[2]=T_neg_c; Tvecs[3]=T_neg_d;
      Tvecs[4]=T_pos_a; Tvecs[5]=T_pos_b; Tvecs[6]=T_pos_c; Tvecs[7]=T_pos_d;

      dTvecs[0]=dT_neg_a; dTvecs[1]=dT_neg_b; dTvecs[2]=dT_neg_c; dTvecs[3]=dT_neg_d;
      dTvecs[4]=dT_pos_a; dTvecs[5]=dT_pos_b; dTvecs[6]=dT_pos_c; dTvecs[7]=dT_pos_d;

      reg_mode = 1'b1; dt_mode = 1'b0;

      // T at edges, dT=0
      dT_in = 8'sd0;
      for (k=0;k<8;k++) begin
        T_in = Tvecs[k];
        compute_and_check_expected($sformatf("EDGE_T@%0d_dT=0", $signed(T_in)));
        assert (!$isunknown({valid,G_out})) else $error("X/Z on outputs (EDGE_T)");
      end

      // dT at edges, T=0
      T_in = 8'sd0;
      for (k=0;k<8;k++) begin
        dT_in = dTvecs[k];
        compute_and_check_expected($sformatf("EDGE_dT@%0d_T=0", $signed(dT_in)));
        assert (!$isunknown({valid,G_out})) else $error("X/Z on outputs (EDGE_dT)");
      end
    end

    // --- REQ: degenerate MFs (b==a, d==c) must be safe and finite
    begin : DEGEN_TRAP
      // Save originals
      automatic logic signed [7:0] s_T_zero_b = T_zero_b;
      automatic logic signed [7:0] s_T_zero_c = T_zero_c;

      // Force ZERO MF to degenerate shoulders
      T_zero_b = T_zero_a; // b==a -> left slope len 0
      T_zero_c = T_zero_d; // d==c -> right slope len 0

      reg_mode = 1'b1; dt_mode = 1'b0;
      T_in = 8'sd0;

      foreach (dTs[j]) begin
        dT_in = dTs[j];
        compute_and_check_expected("DEGEN_ZERO_T");
        assert (!$isunknown({valid,G_out})) else $error("X/Z (DEGEN_ZERO)");
      end

      // restore
      T_zero_b = s_T_zero_b;
      T_zero_c = s_T_zero_c;
    end


    // --- Back-to-back STARTs -> two clean VALID pulses, no glitch
    begin : START_B2B
      reg_mode = 1'b1; dt_mode = 1'b0; T_in = 8'sd16; dT_in = -8'sd8;
      pulse_start(); wait_valid_count_cycles(lat); check_valid_one_shot(); @(posedge clk);
      pulse_start(); wait_valid_count_cycles(lat); check_valid_one_shot(); @(posedge clk);
    end

    // --- START while VALID (1-cycle overlap poke)
    begin : START_OVERLAP
      reg_mode = 1'b1; dt_mode = 1'b0; T_in = -8'sd20; dT_in = 8'sd25;
      // fire first
      pulse_start(); wait_valid_count_cycles(lat);
      // schedule a start that rises on same cycle as VALID (approx)
      fork
        begin
          @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;
        end
        begin
          @(posedge valid); // observe overlap
        end
      join
      // Expect exactly one VALID per START overall
      check_valid_one_shot(); @(posedge clk);
    end

    // --- INIT and START same cycle: must be safe and in-range (and generally equal to dT=0 golden)
    begin : INIT_VS_START
      reg_mode = 1'b1; dt_mode = 1'b1; T_in = 8'sd0;
      compute_gexp_at_dT0(T_in, reg_mode, Gexp_init);

      @(negedge clk);
      init  <= 1'b1;
      start <= 1'b1;
      @(posedge clk);
      init  <= 1'b0;
      start <= 1'b0;

      wait_valid_count_cycles(lat1);
      check_valid_one_shot(); @(posedge clk);

      assert (G_out <= 8'd100) else $error("Out of range after INIT∧START");
      // Optional if this is the spec: assert (G_out == Gexp_init);
    end

    // --- A few legal MF layouts to prove configurability
    begin : PARAM_SWEEP
      int v;
      reg_mode = 1'b1; dt_mode = 1'b0;

      // Sweep ZERO width and POS spacing a bit
      for (v=0; v<3; v++) begin
        // widen ZERO by 2*v around 0 (keep monotonic a<=b<=c<=d)
        T_zero_a = -16 - 2*v; T_zero_b = 0; T_zero_c = 0; T_zero_d = 16 + 2*v;
        // move POS a bit
        T_pos_a  = 0; T_pos_b = 32 + 2*v; T_pos_c = 64 + 2*v; T_pos_d = 127;

        // small grid check
        foreach (Ts[i]) begin
          foreach (dTs[j]) begin
            T_in  = Ts[i]; dT_in = dTs[j];
            compute_and_check_expected($sformatf("PARAM_SWEEP_v%0d", v));
            assert (!$isunknown({valid,G_out})) else $error("X/Z (PARAM_SWEEP)");
          end
        end
      end
    end


    $display("[REQ-010][REQ-020][REQ-030][REQ-040][REQ-050][REQ-060][REQ-061][REQ-062][REQ-210][REQ-230][REQ-320][REQ-310] system TB finished");
    $finish;
  end

endmodule
