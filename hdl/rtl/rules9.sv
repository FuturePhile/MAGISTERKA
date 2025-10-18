// REQ: 030,040
module rules9(
  input  logic [15:0] muT_neg, muT_zero, muT_pos,
  input  logic [15:0] muD_neg, muD_zero, muD_pos,
  output logic [15:0] w00, w01, w02, w10, w11, w12, w20, w21, w22
);
  function automatic [15:0] fmin(input [15:0] a,b); fmin=(a<b)?a:b; endfunction
  always_comb begin
    w00=fmin(muT_neg ,muD_neg ); w01=fmin(muT_neg ,muD_zero); w02=fmin(muT_neg ,muD_pos );
    w10=fmin(muT_zero,muD_neg ); w11=fmin(muT_zero,muD_zero); w12=fmin(muT_zero,muD_pos );
    w20=fmin(muT_pos ,muD_neg ); w21=fmin(muT_pos ,muD_zero); w22=fmin(muT_pos ,muD_pos );
  end
endmodule
