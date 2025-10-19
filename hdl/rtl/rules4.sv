// REQ: 030,040
module rules4(
  input  logic [15:0] muT_neg, 
  input  logic [15:0] muT_pos,
  input  logic [15:0] muD_neg, 
  input  logic [15:0] muD_pos,
  output logic [15:0] w_nn, 
  output logic [15:0] w_np, 
  output logic [15:0] w_pn, 
  output logic [15:0] w_pp
);

  function automatic [15:0] fmin(input [15:0] a, b); 
    fmin = (a < b) ? a : b; 
  endfunction

  always_comb begin
    w_nn = fmin(muT_neg, muD_neg);
    w_np = fmin(muT_neg, muD_pos);
    w_pn = fmin(muT_pos, muD_neg);
    w_pp = fmin(muT_pos, muD_pos);
  end

endmodule
