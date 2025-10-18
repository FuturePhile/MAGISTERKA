// REQ: 030,040
module rules4(
  input  logic [15:0] muT_neg, muT_pos,
  input  logic [15:0] muD_neg, muD_pos,
  output logic [15:0] w_nn, w_np, w_pn, w_pp
);
  function automatic [15:0] fmin(input [15:0] a,b); fmin=(a<b)?a:b; endfunction
  always_comb begin
    w_nn=fmin(muT_neg,muD_neg);
    w_np=fmin(muT_neg,muD_pos);
    w_pn=fmin(muT_pos,muD_neg);
    w_pp=fmin(muT_pos,muD_pos);
  end
endmodule
