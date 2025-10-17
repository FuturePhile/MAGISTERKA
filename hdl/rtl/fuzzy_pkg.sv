//------------------------------------------------------------------------------
// fuzzy_pkg.sv  -- stałe, typy, pomocnicze funkcje  (REQ-210)
//------------------------------------------------------------------------------
package fuzzy_pkg;

  // Q-formaty
  localparam int Q15_ONE = 16'sd32767;  // ~1.0 w Q1.15

  // Bezpieczna saturacja do 16-bit bez znaku
  function automatic logic [15:0] sat_u16 (input logic signed [31:0] x);
    if (x < 0)        return 16'd0;
    else if (x > 32'sd65535) return 16'hFFFF;
    else              return x[15:0];
  endfunction

  // Saturacja do int8 (Q7.0)
  function automatic logic signed [7:0] sat_s8 (input logic signed [15:0] x);
    if (x < -128) return -128;
    else if (x > 127) return 127;
    else return x[7:0];
  endfunction

  // min na Q1.15
  function automatic logic [15:0] q15_min (input logic [15:0] a, b);
    return (a < b) ? a : b;
  endfunction

  // Konwersja g[%0..100] -> Q1.15
  function automatic logic [15:0] g_percent_to_q15 (input logic [7:0] g);
    // (g/100.0)*32767  ≈ (g * 32767 + 50)/100
    logic [23:0] mul = g * 16'd32767;
    return ((mul + 24'd50) / 100);
  endfunction

endpackage
