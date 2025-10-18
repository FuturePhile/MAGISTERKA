// REQ: 050,210
module defuzz(
  input  logic       clk, rst_n,
  input  logic [15:0] S_w,
  input  logic [15:0] S_wg,
  output logic [7:0]  G_out
);
  localparam logic [15:0] EPS = 16'd1;
  logic [15:0] den;
  logic [31:0] ratio, perc;
  logic [7:0]  sat;

  always_comb begin
    den   = (S_w < EPS) ? EPS : S_w;
    ratio = ( (S_wg << 15) / den );      // Q1.15
    perc  = ( ratio * 32'd100 ) >> 15;   // 0..100
    sat   = (perc > 32'd100) ? 8'd100 : perc[7:0];
  end

  always_ff @(posedge clk or negedge rst_n)
    if(!rst_n) G_out <= 8'd0;
    else       G_out <= sat;
endmodule
