// defuzz.v — G = round((S_wg / max(S_w, EPS)) * 100) bez dzielenia
// Q1.15 wejścia, wynik 0..100 %
// Wymaga pliku inv_q15.hex (256 x 16) — ten sam co w trapezoid.v
module defuzz (
  input         clk,
  input         rst_n,
  input  [15:0] S_w,      // Q1.15
  input  [15:0] S_wg,     // Q1.15
  output reg [7:0] G_out  // 0..100
);
  localparam [15:0] EPS = 16'd1;   // 1 LSB Q1.15

  // ROM z odwrotnościami: inv[k] = floor(2^15 / max(k,1)), k=0..255
  reg [15:0] inv_q15 [0:255];
  initial begin
    // Podaj pełną ścieżkę jeśli trzeba (ISE: Add Source -> inv_q15.hex)
    $readmemh("inv_q15.hex", inv_q15);
  end

  // robocze sygnały
  reg  [15:0] den_q15;         // max(S_w, EPS)
  reg  [7:0]  mant;            // 8-bit znormalizowana mantysa (128..255)
  reg  [3:0]  sh;              // przesunięcie (0..15)
  reg  [4:0]  msb;             // pozycja MSB den
  reg  [17:0] inv_den_q15;     // "1/den" w Q0.15 (poszerzone o ewentualne lewo-shifty)
  reg  [33:0] prod_ratio;      // S_wg * inv_den (do 34 bit)
  reg  [15:0] ratio_q15;       // Q1.15
  reg  [31:0] percent_u;       // przed saturacją
  reg  [7:0]  sat_u8;

  // funkcja: pozycja najwyższego '1' w 16-bit (0..15), dla zera zwraca 0
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

  // Uwaga: ręczna lista czułości — bez 'inv_q15'
  always @(S_w or S_wg) begin
    // 1) zabezpiecz dzielnik
    den_q15 = (S_w < EPS) ? EPS : S_w;

    // 2) normalizacja do mantysy 8-bit i przesunięcia
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
      sh   = 4'd7 - msb[3:0];   // 1..7 (dla den>=1)
      mant = (den_q15 << sh);
      if (mant < 8'd1)   mant = 8'd1;
      if (mant > 8'd255) mant = 8'd255;
      inv_den_q15 = {2'b00, inv_q15[mant]} << sh; // poszerz na zapas
    end

    // 3) ratio ≈ S_wg * inv_den_q15  (Q1.15)
    prod_ratio = S_wg * inv_den_q15;  // do 34 bit
    // wynik w Q1.15 ~ prod_ratio (bo inv_den_q15 to Q0.15); zetnij/saturuj
    if (prod_ratio[33:16] != 18'd0) begin
      ratio_q15 = 16'h7FFF; // saturacja w górę, gdyby przeszacowało
    end else begin
      ratio_q15 = prod_ratio[15:0];
    end

    // 4) percent = round(ratio_q15 * 100 / 2^15)
    // użyj tej samej sztuczki co wcześniej: (x*100 + 2^14) >> 15
    percent_u = (ratio_q15 * 32'd100 + 32'd16384) >> 15;
    sat_u8    = (percent_u > 32'd100) ? 8'd100 : percent_u[7:0];
  end

  // rejestr wyjściowy (latencja 1 cykl jak wcześniej)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) G_out <= 8'd0;
    else        G_out <= sat_u8;
  end
endmodule
