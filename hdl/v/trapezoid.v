// trapezoid.v — trapezoid/triangle MF bez dzielenia (XST-safe)
// Q7.0 wejścia, Q1.15 wyjście
module trapezoid (
  input  signed [7:0] x,
  input  signed [7:0] a,
  input  signed [7:0] b,
  input  signed [7:0] c,
  input  signed [7:0] d,
  output reg   [15:0] mu
);
  // ROM 256x16 z odwrotnościami w Q0.15: inv[k] = floor(2^15/max(k,1))
  reg [15:0] inv_q15 [0:255];
  initial begin
    // Upewnij się, że plik jest w tym samym folderze co .v lub podaj pełną ścieżkę
    // np. $readmemh("C:/Xilinx/projects/MGR/inv_q15.hex", inv_q15);
    $readmemh("inv_q15.hex", inv_q15);
  end

  // robocze
  reg [8:0]  den;       // szerzej, by policzyć różnice
  reg [7:0]  den8;      // indeks ROM (0..255, z ochroną)
  reg [8:0]  delta;     // 0..den-1
  reg [23:0] prod;      // 9b * 16b

  // UWAGA: ręczna lista czułości — bez inv_q15!
  always @(x or a or b or c or d) begin
    mu    = 16'd0;
    den   = 9'd1;
    den8  = 8'd1;
    delta = 9'd0;
    prod  = 24'd0;

    if ((x <= a) || (x >= d)) begin
      mu = 16'd0;
    end
    else if ((x >= b) && (x <= c)) begin
      mu = 16'h7FFF; // ~1.0
    end
    else if ((x > a) && (x < b)) begin
      // lewe zbocze: (x-a)/(b-a)
      den   = $unsigned($signed(b) - $signed(a));
      if (den == 9'd0) den = 9'd1;      // ochrona
      den8  = den[7:0] | {8{den[8]}};   // gdy >255, ustaw na 255
      delta = $unsigned($signed(x) - $signed(a));
      if (delta > den) delta = den;     // asekuracja
      prod  = delta * inv_q15[den8];    // < 2^15
      mu    = prod[15:0];
    end
    else begin
      // prawe zbocze: (d-x)/(d-c)
      den   = $unsigned($signed(d) - $signed(c));
      if (den == 9'd0) den = 9'd1;
      den8  = den[7:0] | {8{den[8]}};
      delta = $unsigned($signed(d) - $signed(x));
      if (delta > den) delta = den;
      prod  = delta * inv_q15[den8];
      mu    = prod[15:0];
    end
  end
endmodule
