`timescale 1ns/1ps

module tb_rules_agg_defuzz;
  // μ inputs (Q1.15)
  logic [15:0] muT_neg, muT_zero, muT_pos;
  logic [15:0] muD_neg, muD_zero, muD_pos;

  // rules
  logic [15:0] w00,w01,w02,w10,w11,w12,w20,w21,w22;

  // aggregator
  logic        reg_mode;
  logic [7:0]  g00,g01,g02,g10,g11,g12,g20,g21,g22;
  logic [15:0] S_w, S_wg;

  // defuzz (registered)
  logic clk=0,rst_n=0;
  logic [7:0] G_out;
  always #5 clk=~clk;

  // DUTs
  rules9 u_rules9 (
    .muT_neg (muT_neg), .muT_zero(muT_zero), .muT_pos(muT_pos),
    .muD_neg (muD_neg), .muD_zero(muD_zero), .muD_pos(muD_pos),
    .w00(w00),.w01(w01),.w02(w02),
    .w10(w10),.w11(w11),.w12(w12),
    .w20(w20),.w21(w21),.w22(w22)
  );

  aggregator u_aggregator (
    .reg_mode (reg_mode),
    .w00(w00), .w01(w01), .w02(w02),
    .w10(w10), .w11(w11), .w12(w12),
    .w20(w20), .w21(w21), .w22(w22),
    .g00(g00), .g01(g01), .g02(g02),
    .g10(g10), .g11(g11), .g12(g12),
    .g20(g20), .g21(g21), .g22(g22),
    .S_w(S_w), .S_wg(S_wg)
  );

  defuzz u_defuzz (
    .clk(clk), .rst_n(rst_n),
    .S_w(S_w), .S_wg(S_wg),
    .G_out(G_out)
  );

  // ---------- helpers (mirror RTL math) ----------
  localparam int HALF_LSB = 1<<14;

  function automatic [15:0] g2q15 (input [7:0] gpct);
    int unsigned tmp;
    begin
      tmp   = gpct * 32767 + 50; // clamp/round like RTL
      tmp   = tmp / 100;
      g2q15 = (tmp > 32767) ? 16'd32767 : tmp[15:0];
    end
  endfunction

  function automatic [15:0] mul_q15 (input [15:0] w, input [7:0] g_pct);
    int unsigned prod;
    begin
      prod = (w * g2q15(g_pct)) + HALF_LSB; // rounding
      return prod >> 15;
    end
  endfunction

  function automatic int q15_to_pct(input [15:0] q); return (q * 100) >>> 15; endfunction

  // ---------- test ----------
  initial begin
    int Sw_pct;       // declare here
    int exp_Sw_q15;
    int exp_Swg_q15;
    int exp_pct;
    
    rst_n=0; repeat(2) @(posedge clk); rst_n=1; @(posedge clk);

    // CASE 1: only (pos,pos)=0.5 active, g22=100% => G ≈ 50
    muT_neg=0; muT_zero=0; muT_pos=16'h4000;
    muD_neg=0; muD_zero=0; muD_pos=16'h4000;
    reg_mode = 1'b1;
    {g00,g01,g02,g10,g11,g12,g20,g21,g22} =
      {8'd0,8'd0,8'd0, 8'd0,8'd0,8'd0, 8'd0,8'd0,8'd100};

    @(posedge clk);
    Sw_pct = q15_to_pct(S_w);
    assert(Sw_pct >= 49 && Sw_pct <= 51) else $fatal("REQ-040: S_w ~0.5, got %0d%%", Sw_pct);
     @(posedge clk);
    assert(G_out >= 8'd49 && G_out <= 8'd51) else $fatal("REQ-050: G≈50, got %0d", G_out);

    // CASE 2: w11=w22=0.5, g11=30, g22=80 => ~55%
    muT_neg=0; muT_zero=16'h4000; muT_pos=16'h4000;
    muD_neg=0; muD_zero=16'h4000; muD_pos=16'h4000;
    {g00,g01,g02,g10,g11,g12,g20,g21,g22} =
      {8'd0,8'd0,8'd0, 8'd0,8'd30,8'd0, 8'd0,8'd0,8'd80};
    @(posedge clk); @(posedge clk);
    // expected with exact RTL math:
    exp_Sw_q15  = 16'h4000 + 16'h4000; // 0.5+0.5 = 1.0
    exp_Swg_q15 = mul_q15(16'h4000,8'd30) + mul_q15(16'h4000,8'd80);
    exp_pct     = ( (exp_Swg_q15 << 15) / (exp_Sw_q15==0?1:exp_Sw_q15) ) * 100 >>> 15;
    assert(G_out >= (exp_pct-1) && G_out <= (exp_pct+1))
      else $fatal("REQ-040/050: mix exp=%0d got=%0d", exp_pct, G_out);

    // CASE 3: REG_MODE=0 should gate center/edges (only corners contribute)
    reg_mode = 1'b0;
    // center weights are 0.5 now but must be ignored
    {g00,g01,g02,g10,g11,g12,g20,g21,g22} =
      {8'd10,8'd20,8'd30, 8'd40,8'd50,8'd60, 8'd70,8'd80,8'd90};
    @(posedge clk); @(posedge clk);
    // Only corners remain in S_w/S_wg; just sanity band check:
    assert(q15_to_pct(S_w) <= 60) else $fatal("REQ-050: REG_MODE=0 should reduce Σw");

    // CASE 4: S_w == 0 -> epsilon path in defuzz → G_out = 0
    muT_neg=0; muT_zero=0; muT_pos=0;
    muD_neg=0; muD_zero=0; muD_pos=0;
    @(posedge clk); @(posedge clk);
    assert(S_w==0) else $fatal("internal: S_w not zero");
    assert(G_out==0) else $fatal("REQ-050: epsilon guard, G must be 0");

    // CASE 5: Saturation — all w=1.0, all g=100% → G=100 and Σ not overflow
    muT_neg=16'h7FFF; muT_zero=16'h7FFF; muT_pos=16'h7FFF;
    muD_neg=16'h7FFF; muD_zero=16'h7FFF; muD_pos=16'h7FFF;
    reg_mode = 1'b1;
    {g00,g01,g02,g10,g11,g12,g20,g21,g22} =
      {9{8'd100}};
    @(posedge clk); @(posedge clk);
    assert(G_out >= 99) else $fatal("REQ-040/050: saturation case G~100, got %0d", G_out);

    $display("tb_rules_agg_defuzz: PASS");
    $finish;
  end
endmodule
