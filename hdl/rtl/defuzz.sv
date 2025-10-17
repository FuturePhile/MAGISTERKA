//------------------------------------------------------------------------------
// defuzz.sv -- średnia ważona: G = (Σ w*g) / (Σ w)  (REQ-050)
// Wejścia: S_w  (Q1.15 sumowane -> <=24b), S_wg (Q2.30 -> 32b)
// Wyjście: G_percent [7:0] (0..100)
//------------------------------------------------------------------------------
module defuzz (
  input  logic        clk,
  input  logic        start,
  input  logic [23:0] S_w,
  input  logic [31:0] S_wg,
  output logic        valid,
  output logic [7:0]  G_percent
);
  // Prosty, 2-cyklowy pipeline z ochroną S_w==0
  logic [31:0] S_wg_r;
  logic [23:0] S_w_r;
  logic        v1, v2;

  always_ff @(posedge clk) begin
    if (start) begin
      S_wg_r <= S_wg;
      S_w_r  <= S_w;
      v1     <= 1'b1;
    end else begin
      v1 <= 1'b0;
    end
  end

  // Dzielenie: (S_wg >> 15) / (S_w >> 15) ~= (S_wg / S_w)
  // Upraszczamy: skaluje do Q1.15 przed dzieleniem, potem *100 i clamp.
  logic [31:0] num_q16;  // przybliżenie do 16 bitów frakcji
  logic [23:0] den_q16;
  logic [31:0] ratio_q16;
  always_ff @(posedge clk) begin
    // zabezpieczenie przed 0
    if (S_w_r == 0) begin
      ratio_q16 <= 0;
    end else begin
      num_q16 <= S_wg_r >> 15;        // Q2.30 -> Q2.15
      den_q16 <= S_w_r;               // Q1.15 sumy
      ratio_q16 <= num_q16 / den_q16; // ~Q1.0..Q1.15
    end
    v2 <= v1;
  end

  // Skala do 0..100%
  always_ff @(posedge clk) begin
    valid <= v2;
    if (v2) begin
      // ratio_q16 ~ Q1.15; *100 i zaokrąglenie
      logic [31:0] tmp = (ratio_q16 * 100 + 16'd16384) >> 15;
      if (tmp > 100) G_percent <= 8'd100;
      else           G_percent <= tmp[7:0];
    end
  end
endmodule
