// dt_estimator.sv — EMA of T[n]-T[n-1] with saturation
// REQ-060: internal dT estimation when DT_MODE=1
// REQ-061: parameters ALPHA (~/256), K_DT (2^k), D_MAX clamp in Q7.0
// REQ-062: INIT pulse resets estimator without output spike
// REQ-210: fixed-point internal Q1.15

module dt_estimator (
  input  logic              clk,
  input  logic              rst_n,
  input  logic signed [7:0] T_cur,     // Q7.0
  input  logic       [7:0]  alpha,     // 0..255, ~alpha/256
  input  logic       [7:0]  k_dt,      // scale divider 2^k (0..7 suggested)
  input  logic       [7:0]  d_max,     // abs clamp in Q7.0
  input  logic              init,      // 1-cycle pulse
  output logic signed [7:0] dT_out,    // Q7.0
  output logic              dt_valid
);

  // State registers
  logic signed [7:0]  T_prev;
  logic signed [15:0] dT_prev_q15;     // Q1.15 internal

  // Delta and scaling
  logic signed [8:0]  delta_q8;        // Q8.0
  logic signed [15:0] delta_q15;       // Q1.15
  logic signed [15:0] delta_scaled;    // Q1.15

  // EMA arithmetic
  logic [15:0] alpha_q;  // Q8.8
  logic [15:0] one_q;    // 1.0 = 256 in Q8.8
  logic [15:0] inv_a;    // (1 - alpha)
  logic signed [31:0] term1, term2, sum32;
  logic signed [15:0] dT_new_q15;      // Q1.15

  // Clamp
  logic signed [15:0] dmax_q15, clip_hi, clip_lo; // Q1.15

  // Combinational math
  always_comb begin
    // ∆T in Q8.0
    delta_q8     = $signed({{1{T_cur[7]}},  T_cur}) - $signed({{1{T_prev[7]}}, T_prev});

    // Q8.0 → Q1.15  (<< 15 — popr. skala)
    delta_q15    = $signed(delta_q8) <<< 15;

    // Scale by 2^k (arith.) — stays in Q1.15
    delta_scaled = delta_q15 >>> k_dt;

    // EMA weights in Q8.8
    alpha_q = {8'b0, alpha};
    one_q   = 16'd256;
    inv_a   = one_q - alpha_q;

    // Multiply and accumulate: (Q1.15 * Q8.8)<<8 → 32b align, then >>16 → Q1.15
    term1 = $signed(dT_prev_q15) * $signed({inv_a,  8'b0});
    term2 = $signed(delta_scaled) * $signed({alpha_q,8'b0});
    sum32 = term1 + term2;
    dT_new_q15 = sum32[31:16]; // Q1.15

    // Clamp in Q1.15 (D_MAX w Q7.0 → Q1.15)
    dmax_q15 = $signed(d_max) <<< 15;
    clip_hi  = (dT_new_q15 >  dmax_q15) ?  dmax_q15 : dT_new_q15;
    clip_lo  = (clip_hi    < -dmax_q15) ? -dmax_q15 : clip_hi;
  end

  // Sequential update with INIT behavior
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      T_prev       <= '0;
      dT_prev_q15  <= '0;
      dT_out       <= '0;
      dt_valid     <= 1'b0;
    end else if (init) begin
      // capture current T so the next delta is 0; clear EMA state
      T_prev       <= T_cur;
      dT_prev_q15  <= '0;
      dT_out       <= '0;
      dt_valid     <= 1'b0;
    end else begin
      // update state
      T_prev       <= T_cur;
      dT_prev_q15  <= clip_lo;

      // Q1.15 → int8 (Q7.0), truncation toward zero (avoid -1 drift)
      if (clip_lo < 0)
        dT_out <= ($signed(clip_lo) + 16'sd32767) >>> 15; // + (2^15-1), then >>15
      else
        dT_out <=  clip_lo >>> 15;

      dt_valid     <= 1'b1;
    end
  end

endmodule
