// dt_estimator.sv - EMA of T[n]-T[n-1] with saturation
// REQ-060: internal dT estimation when DT_MODE=1
// REQ-061: parameters ALPHA (~/256), K_DT (2^k), D_MAX clamp in Q7.0
// REQ-062: INIT pulse resets estimator without output spike
// REQ-210: internal fixed-point Q0.7 (legacy name "*_q15" kept)

module dt_estimator (
  input  logic              clk,
  input  logic              rst_n,
  input  logic signed [7:0] T_cur,      // Q7.0
  input  logic       [7:0]  alpha,      // 0..255, approx alpha/256
  input  logic       [7:0]  k_dt,       // scale divider 2^k (0..7 suggested)
  input  logic       [7:0]  d_max,      // abs clamp in Q7.0
  input  logic              init,       // 1-cycle pulse
  output logic signed [7:0] dT_out,     // Q7.0
  output logic              dt_valid
);

  // State
  logic signed [7:0]  T_prev;           // Q7.0
  logic signed [15:0] dT_prev_q15;      // Q0.7

  // Comb temporaries
  logic        [3:0]  k_dt_lim;         // safe shift 0..7
  logic signed [8:0]  delta_q8;         // Q8.0
  logic signed [15:0] delta_q07;        // Q0.7
  logic signed [15:0] delta_scaled;     // Q0.7
  logic       [15:0]  inv_a_u;          // 0..256
  logic       [15:0]  a_u;              // 0..255
  logic signed [31:0] term1;            // Q0.7 * int
  logic signed [31:0] term2;            // Q0.7 * int
  logic signed [31:0] sum32;            // Q0.7 * int
  logic signed [15:0] dT_new_q15;       // Q0.7
  logic signed [15:0] dmax_q15;         // Q0.7
  logic signed [15:0] clamped_q15;      // Q0.7
  logic signed [7:0]  q07_to_s8;        // Q7.0

  // Combinational path
  always_comb begin
    k_dt_lim    = (k_dt > 8'd7) ? 4'd7 : k_dt[3:0];
    delta_q8    = $signed({{1{T_cur[7]}}, T_cur}) - $signed({{1{T_prev[7]}}, T_prev});
    delta_q07   = $signed(delta_q8) <<< 7;
    delta_scaled= delta_q07 >>> k_dt_lim;

    inv_a_u     = 16'd256 - {8'd0, alpha};
    a_u         = {8'd0, alpha};

    term1       = $signed(dT_prev_q15) * $signed(inv_a_u);
    term2       = $signed(delta_scaled) * $signed(a_u);
    sum32       = term1 + term2;
    dT_new_q15  = $signed(sum32 >>> 8);

    dmax_q15    = $signed(d_max) <<< 7;
    clamped_q15 = (dT_new_q15 >  dmax_q15) ?  dmax_q15 : dT_new_q15;
    clamped_q15 = (clamped_q15 < -dmax_q15) ? -dmax_q15 : clamped_q15;

    // Truncate toward zero for negative values before Q0.7 -> Q7.0
    q07_to_s8   = $signed(((clamped_q15 < 0) ? (clamped_q15 + 16'sd127) : clamped_q15) >>> 7);
  end

  // Sequential update with INIT handling
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      T_prev      <= 8'sd0;
      dT_prev_q15 <= 16'sd0;
      dT_out      <= 8'sd0;
      dt_valid    <= 1'b0;
    end else if (init) begin
      T_prev      <= T_cur;
      dT_prev_q15 <= 16'sd0;
      dT_out      <= 8'sd0;
      dt_valid    <= 1'b0;
    end else begin
      T_prev      <= T_cur;
      dT_prev_q15 <= clamped_q15;
      dT_out      <= q07_to_s8;
      dt_valid    <= 1'b1;
    end
  end

endmodule
