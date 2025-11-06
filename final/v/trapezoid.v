// trapezoid.v - trapezoid/triangle MF without division (XST-safe)
// Inputs Q7.0, output Q1.15
module trapezoid (
  input  signed [7:0] x,
  input  signed [7:0] a,
  input  signed [7:0] b,
  input  signed [7:0] c,
  input  signed [7:0] d,
  output reg   [15:0] mu
);
  // ROM 256x16 with reciprocals in Q0.15: inv[k] = floor(2^15 / max(k,1))
  reg [15:0] inv_q15 [0:255];
  initial begin
    // Make sure the file is in the same folder as this .v or provide a full path
    // e.g. $readmemh("C:/Xilinx/projects/MGR/inv_q15.hex", inv_q15);
    $readmemh("inv_q15.hex", inv_q15);
  end

  // working registers
  reg [8:0]  den;       // wider to compute differences
  reg [7:0]  den8;      // ROM index (0..255, with protection)
  reg [8:0]  delta;     // 0..den-1
  reg [23:0] prod;      // 9b * 16b

  // NOTE: manual sensitivity list — without inv_q15!
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
      // left slope: (x-a)/(b-a)
      den   = $unsigned($signed(b) - $signed(a));
      if (den == 9'd0) den = 9'd1;      // protect from zero
      den8  = den[7:0] | {8{den[8]}};   // if >255, force to 255
      delta = $unsigned($signed(x) - $signed(a));
      if (delta > den) delta = den;     // guard
      prod  = delta * inv_q15[den8];    // < 2^15
      mu    = prod[15:0];
    end
    else begin
      // right slope: (d-x)/(d-c)
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
