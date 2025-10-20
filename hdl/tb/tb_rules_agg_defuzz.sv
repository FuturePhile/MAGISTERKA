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

  // defuzz
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

  // helper
  function int q15_to_pct(input [15:0] q);
    return (q * 100) >>> 15;
  endfunction

  initial begin
    // Reset
    rst_n=0; repeat(2) @(posedge clk); rst_n=1; @(posedge clk);

    // Case 1: Only (pos,pos) active ~0.5, g22=100% => expect G ~50..55%
    muT_neg=0; muT_zero=0; muT_pos=16'h4000; // 0.5
    muD_neg=0; muD_zero=0; muD_pos=16'h4000;
    reg_mode = 1'b1;
    {g00,g01,g02,g10,g11,g12,g20,g21,g22} = {8'd0,8'd0,8'd0, 8'd0,8'd0,8'd0, 8'd0,8'd0,8'd100};
    @(posedge clk);
    assert(q15_to_pct(S_w) >= 49 && q15_to_pct(S_w) <= 51) else $fatal("REQ-040 FAIL: S_w ~0.5");
    @(posedge clk);
    assert(G_out >= 8'd49 && G_out <= 8'd51) else $fatal("REQ-050 FAIL: G ≈ 50, got %0d", G_out);

    // Case 2: Two rules active equally (w11=w22=0.5), g11=30%, g22=80% => expect G ~ (0.5*(0.3)+0.5*(0.8))/1.0 = 55%
    muT_neg=0; muT_zero=16'h4000; muT_pos=16'h4000; // both zero and pos 0.5
    muD_neg=0; muD_zero=16'h4000; muD_pos=16'h4000;
    {g00,g01,g02,g10,g11,g12,g20,g21,g22} = {8'd0,8'd0,8'd0, 8'd0,8'd30,8'd0, 8'd0,8'd0,8'd100};
    @(posedge clk); @(posedge clk);
    assert(G_out >= 8'd53 && G_out <= 8'd57) else $fatal("REQ-040/050 FAIL: mix ~55 got %0d", G_out);

    $display("tb_rules_agg_defuzz: PASS");
    $finish;
  end
endmodule
