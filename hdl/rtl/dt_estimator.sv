//------------------------------------------------------------------------------
// dt_estimator.sv -- EMA różnicy T (REQ-060..062)
// Δ = (T - T_prev) >> K_DT; dT = (1-α)*dT_prev + α*Δ; clamp ±D_MAX
// We/wy w Q7.0 (int8), wewnątrz poszerzamy do 16b
//------------------------------------------------------------------------------
module dt_estimator (
  input  logic              clk,
  input  logic              rst,        // synchroniczny
  input  logic              init,       // CTRL.INIT
  input  logic signed [7:0] T_in,       // Q7.0
  input  logic       [7:0]  ALPHA,      // α ≈ ALPHA/256
  input  logic       [7:0]  K_DT,       // dzielnik 2^K
  input  logic signed [7:0] D_MAX,      // clamp
  output logic signed [7:0] dT_out      // Q7.0
);
  logic signed [7:0] T_prev;
  logic signed [15:0] dT_acc; // Q7.8 „robocze”

  always_ff @(posedge clk) begin
    if (rst || init) begin
      T_prev <= T_in;
      dT_acc <= '0;
      dT_out <= '0;
    end else begin
      // Δ = (T - T_prev) >> K_DT
      logic signed [15:0] delta = (T_in - T_prev);
      logic signed [15:0] delta_s = delta >>> K_DT;

      // dT_acc = (255-ALPHA)/256 * dT_acc + ALPHA/256 * (delta_s << 8)
      logic [15:0] one = 16'd256;
      logic [15:0] a   = {8'd0, ALPHA};      // 0..256
      logic [15:0] oma = one - a;

      logic signed [23:0] part1 = $signed(oma) * $signed(dT_acc);           // Q7.8 * 8.8
      logic signed [23:0] part2 = $signed(a)   * $signed(delta_s <<< 8);    // przeniesienie do Q7.8

      logic signed [23:0] sum   = part1 + part2;
      dT_acc <= sum >>> 8; // z powrotem Q7.8

      // wyjście Q7.0 z clampem
      logic signed [15:0] dT_q7 = dT_acc >>> 8;
      if (dT_q7 >  D_MAX) dT_out <=  D_MAX;
      else if (dT_q7 < -D_MAX) dT_out <= -D_MAX;
      else dT_out <= dT_q7[7:0];

      T_prev <= T_in;
    end
  end
endmodule
