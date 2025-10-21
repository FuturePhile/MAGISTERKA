`timescale 1ns/1ps
module tb_rules4_vs_rules9;
  // REQ-050: when only corners active, 9-rule ≡ 4-rule
  logic [15:0] muTn,muTz,muTp, muDn,muDz,muDp;
  logic [15:0] w00_9,w01_9,w02_9,w10_9,w11_9,w12_9,w20_9,w21_9,w22_9;
  logic [15:0] w_nn,w_np,w_pn,w_pp;

  rules9 u9(.muT_neg(muTn),.muT_zero(muTz),.muT_pos(muTp),
            .muD_neg(muDn),.muD_zero(muDz),.muD_pos(muDp),
            .w00(w00_9),.w01(w01_9),.w02(w02_9),
            .w10(w10_9),.w11(w11_9),.w12(w12_9),
            .w20(w20_9),.w21(w21_9),.w22(w22_9));
  rules4 u4(.muT_neg(muTn),.muT_pos(muTp),.muD_neg(muDn),.muD_pos(muDp),
            .w_nn(w_nn),.w_np(w_np),.w_pn(w_pn),.w_pp(w_pp));

  initial begin
    // only corners non-zero
    muTn=16'h4000; muTz=0; muTp=16'h4000;
    muDn=16'h2000; muDz=0; muDp=16'h2000;

    #1;
    assert(w00_9==w_nn && w02_9==w_np && w20_9==w_pn && w22_9==w_pp)
      else $fatal("REQ-050 FAIL: corners mismatch 9 vs 4");
    // centers must be zero
    assert(w01_9==0 && w10_9==0 && w11_9==0 && w12_9==0 && w21_9==0);

    $display("tb_rules4_vs_rules9: PASS");
    $finish;
  end
endmodule
