// defuzz.sv - G = round((S_wg / max(S_w, EPS)) * 100)
// REQ-050: safe division with epsilon; output 0..100 % (uint8)
// REQ-210: fixed-point Q1.15 on S_w and S_wg
module defuzz (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [15:0] S_w,     // Q1.15
  input  logic [15:0] S_wg,    // Q1.15
  output logic  [7:0] G_out    // 0..100
);

  localparam logic [15:0] EPS = 16'd1;  // one LSB in Q1.15

  logic [15:0] den_q15;
  logic [31:0] ratio_q15;               // Q1.15
  logic [31:0] percent_u;               // integer 0..100+
  logic  [7:0] sat_u8;

  always_comb begin
    den_q15   = (S_w < EPS) ? EPS : S_w;
    ratio_q15 = (({16'd0, S_wg}) << 15) / den_q15;         // Q1.15
    percent_u = (ratio_q15 * 32'd100 + 32'd16384) >> 15;   // round to nearest
    sat_u8    = (percent_u > 32'd100) ? 8'd100 : percent_u[7:0];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) G_out <= 8'd0; else G_out <= sat_u8;
  end

endmodule
