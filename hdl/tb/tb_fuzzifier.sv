`timescale 1ns/1ps
module tb_fuzzifier;
  // REQ-020: verify (a,b,c,d) mapping and μ ranges for T and dT
  logic signed [7:0] x;
  // simple symmetric triangle a=-64, b=c=0, d=+64
  logic signed [7:0] a=-8'sd64, b=8'sd0, c=8'sd0, d=8'sd64;

  logic [15:0] muTn, muTz, muTp, muDn, muDz, muDp;

  fuzzifier_T  uT (.x(x), .a_neg(a), .b_neg(b), .c_neg(c), .d_neg(d),
                        .a_zero(-8'sd16), .b_zero(-8'sd1), .c_zero(8'sd1), .d_zero(8'sd16),
                        .a_pos(8'sd0), .b_pos(8'sd32), .c_pos(8'sd64), .d_pos(8'sd80),
                        .mu_neg(muTn), .mu_zero(muTz), .mu_pos(muTp));
  fuzzifier_dT uD (.x(x), .a_neg(a), .b_neg(b), .c_neg(c), .d_neg(d),
                        .a_zero(-8'sd16), .b_zero(-8'sd1), .c_zero(8'sd1), .d_zero(8'sd16),
                        .a_pos(8'sd0), .b_pos(8'sd32), .c_pos(8'sd64), .d_pos(8'sd80),
                        .mu_neg(muDn), .mu_zero(muDz), .mu_pos(muDp));

  function int pct(input [15:0] q15); return (q15*100)>>>15; endfunction

  initial begin
    // left outside
    x=-8'sd127; #1; assert(muTn==0 && muDn==0);
    // left slope mid ~50%
    x=-8'sd32; #1; assert(pct(muTn)>=49 && pct(muTn)<=51);
    // plateau ~1.0
    x=8'sd0;   #1; assert(muTn>=16'h7F00 && muDn>=16'h7F00);
    // right slope mid ~50%
    x=8'sd32;  #1; assert(pct(muTp)>=49 && pct(muTp)<=51);
    // right outside
    x=8'sd127; #1; assert(muTp==0 && muDp==0);

    $display("tb_fuzzifier: PASS");
    $finish;
  end
endmodule
