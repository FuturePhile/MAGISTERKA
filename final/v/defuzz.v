// defuzz.v - G = round((S_wg / max(S_w, EPS)) * 100) without divider
// Inputs: Q1.15; output 0..100%
// Requires inv_q15.hex (256 x 16) - same as in trapezoid.v
module defuzz (
  input         clk,
  input         rst_n,
  input  [15:0] S_w,      // Q1.15
  input  [15:0] S_wg,     // Q1.15
  output reg [7:0] G_out  // 0..100
);
  localparam [15:0] EPS = 16'd1;   // 1 LSB in Q1.15

  // ROM of reciprocals: inv[k] = floor(2^15 / max(k,1)), k=0..255
  reg [15:0] inv_q15 [0:255];
  initial begin
    // Provide full path if needed (ISE: Add Source -> inv_q15.hex)
    $readmemh("inv_q15.hex", inv_q15);
  end

  // working signals
  reg  [15:0] den_q15;         // max(S_w, EPS)
  reg  [7:0]  mant;            // 8-bit normalized mantissa (128..255)
  reg  [3:0]  sh;              // shift amount (0..15)
  reg  [4:0]  msb;             // MSB position of den
  reg  [17:0] inv_den_q15;     // "1/den" in Q0.15 (widened for left shifts)
  reg  [33:0] prod_ratio;      // S_wg * inv_den (up to 34 bits)
  reg  [15:0] ratio_q15;       // Q1.15
  reg  [31:0] percent_u;       // pre-saturation
  reg  [7:0]  sat_u8;

  // function: position of highest '1' in 16-bit (0..15), returns 0 for zero
  function [4:0] msb_pos16(input [15:0] v);
    begin
      casex (v)
        16'b1xxxxxxxxxxxxxxx: msb_pos16 = 5'd15;
        16'b01xxxxxxxxxxxxxx: msb_pos16 = 5'd14;
        16'b001xxxxxxxxxxxxx: msb_pos16 = 5'd13;
        16'b0001xxxxxxxxxxxx: msb_pos16 = 5'd12;
        16'b00001xxxxxxxxxxx: msb_pos16 = 5'd11;
        16'b000001xxxxxxxxxx: msb_pos16 = 5'd10;
        16'b0000001xxxxxxxxx: msb_pos16 = 5'd9;
        16'b00000001xxxxxxxx: msb_pos16 = 5'd8;
        16'b000000001xxxxxxx: msb_pos16 = 5'd7;
        16'b0000000001xxxxxx: msb_pos16 = 5'd6;
        16'b00000000001xxxxx: msb_pos16 = 5'd5;
        16'b000000000001xxxx: msb_pos16 = 5'd4;
        16'b0000000000001xxx: msb_pos16 = 5'd3;
        16'b00000000000001xx: msb_pos16 = 5'd2;
        16'b000000000000001x: msb_pos16 = 5'd1;
        default:               msb_pos16 = 5'd0;
      endcase
    end
  endfunction

  // Note: manual sensitivity list - without 'inv_q15'
  always @(S_w or S_wg) begin
    // 1) protect denominator
    den_q15 = (S_w < EPS) ? EPS : S_w;

    // 2) normalize to 8-bit mantissa and shift
    msb = msb_pos16(den_q15);
    if (msb >= 5'd7) begin
      // den >= 128: mant = den >> sh, inv_den = inv[mant] >> sh
      sh   = msb[3:0] - 4'd7;   // 0..8
      mant = (den_q15 >> sh);
      if (mant < 8'd1)   mant = 8'd1;
      if (mant > 8'd255) mant = 8'd255;
      inv_den_q15 = inv_q15[mant] >> sh;
    end else begin
      // den < 128: mant = den << e, inv_den = inv[mant] << e
      sh   = 4'd7 - msb[3:0];   // 1..7 (for den>=1)
      mant = (den_q15 << sh);
      if (mant < 8'd1)   mant = 8'd1;
      if (mant > 8'd255) mant = 8'd255;
      inv_den_q15 = {2'b00, inv_q15[mant]} << sh; // widen for safety
    end

    // 3) ratio ≈ S_wg * inv_den_q15  (Q1.15)
    prod_ratio = S_wg * inv_den_q15;  // up to 34 bits
    // result in Q1.15 ~ prod_ratio (inv_den_q15 is Q0.15); clip/saturate
    if (prod_ratio[33:16] != 18'd0) begin
      ratio_q15 = 16'h7FFF; // saturate up if it overshoots
    end else begin
      ratio_q15 = prod_ratio[15:0];
    end

    // 4) percent = round(ratio_q15 * 100 / 2^15)
    // same trick as above: (x*100 + 2^14) >> 15
    percent_u = (ratio_q15 * 32'd100 + 32'd16384) >> 15;
    sat_u8    = (percent_u > 32'd100) ? 8'd100 : percent_u[7:0];
  end

  // registered output (1-cycle latency as before)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) G_out <= 8'd0;
    else        G_out <= sat_u8;
  end
endmodule
