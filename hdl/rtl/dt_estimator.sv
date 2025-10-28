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
  logic signed [15:0] delta_q07;       // Q0.7
  logic signed [15:0] delta_scaled;    // Q0.7

  // EMA arithmetic
  logic [15:0] alpha_q;  // Q8.8
  logic [15:0] one_q;    // 1.0 = 256 in Q8.8
  logic [15:0] inv_a;    // (1 - alpha)
  logic [15:0] inv_a_u, a_u;   // 0..256
  logic signed [31:0] term1, term2, sum32;
  logic signed [15:0] dT_new_q15;      // Q1.15

  // Clamp
  logic signed [15:0] dmax_q15, clip_hi, clip_lo; // Q1.15

  // Combinational math
  always_comb begin
    // --- ∆T w Q0.7 ---
    delta_q8   = $signed({{1{T_cur[7]}},  T_cur}) - $signed({{1{T_prev[7]}}, T_prev}); // Q8.0
    delta_q07  = $signed(delta_q8) <<< 7;           // Q8.0 → Q0.7
    delta_scaled = delta_q07 >>> k_dt;              // /2^k  (Q0.7)

    // --- Wagi (całkowite): inv_a = 256 - alpha; a = alpha ---
    logic [15:0] inv_a_u = 16'd256 - {8'b0, alpha};
    logic [15:0] a_u     = {8'b0, alpha};

    // --- EMA: (prev*inv_a + delta*a) / 256  (cały tor w Q0.7) ---
    term1 = $signed(dT_prev_q15) * $signed(inv_a_u); // Q0.7 * int → 32b
    term2 = $signed(delta_scaled) * $signed(a_u);    // Q0.7 * int → 32b
    sum32 = term1 + term2;

    // dzielenie przez 256 → wracamy do Q0.7
    dT_new_q15 = $signed(sum32 >>> 8);               // Q0.7

    // --- clamp w Q0.7 (D_MAX też w Q7.0 → Q0.7) ---
    dmax_q15 = $signed(d_max) <<< 7;                 // Q7.0 → Q0.7
    clip_hi  = (dT_new_q15 >  dmax_q15) ?  dmax_q15 : dT_new_q15;
    clip_lo  = (clip_hi    < -dmax_q15) ? -dmax_q15 : clip_hi;
  end


  // Sequential update with INIT behavior
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      T_prev       <= '0;
      dT_prev_q15  <= '0;      // Q0.7
      dT_out       <= '0;      // Q7.0
      dt_valid     <= 1'b0;
    end else if (init) begin
      T_prev       <= T_cur;   // następny delta = 0
      dT_prev_q15  <= '0;      // Q0.7
      dT_out       <= '0;
      dt_valid     <= 1'b0;
    end else begin
      T_prev       <= T_cur;
      dT_prev_q15  <= clip_lo; // Q0.7

      // Q0.7 -> Q7.0 (trunc toward zero, anty-dryf)
      q07_adj <= (clip_lo < 0) ? (clip_lo + 16'sd127) : clip_lo;
      dT_out  <= q07_adj >>> 7;

      dt_valid <= 1'b1;
    end
  end


endmodule
