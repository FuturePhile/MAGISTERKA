// dt_estimator.sv — EMA of T[n]-T[n-1] with saturation
// REQ-060: internal dT estimation when DT_MODE=1
// REQ-061: parameters ALPHA (~/256), K_DT (2^k), D_MAX clamp in Q7.0
// REQ-062: INIT pulse resets estimator without output spike
// REQ-210: fixed-point internal Q0.7 (nazwa „*_q15” pozostawiona dla zgodności)

module dt_estimator (
  input  logic              clk,
  input  logic              rst_n,
  input  logic signed [7:0] T_cur,     // Q7.0
  input  logic       [7:0]  alpha,     // 0..255, ≈ alpha/256
  input  logic       [7:0]  k_dt,      // scale divider 2^k (0..7 suggested)
  input  logic       [7:0]  d_max,     // abs clamp in Q7.0
  input  logic              init,      // 1-cycle pulse
  output logic signed [7:0] dT_out,    // Q7.0
  output logic              dt_valid
);

  // --- Rejestry stanu ---
  logic signed [7:0]  T_prev;
  logic signed [15:0] dT_prev_q15;     // Q0.7 (nazwa historyczna)

  // --- Delta i skalowanie ---
  logic signed [8:0]  delta_q8;        // Q8.0
  logic signed [15:0] delta_q07;       // Q0.7
  logic signed [15:0] delta_scaled;    // Q0.7
  logic        [3:0]  k_dt_lim;        // bezpieczny zakres shifta 0..7

  // --- Arytmetyka EMA ---
  logic [15:0]        inv_a_u, a_u;    // 0..256 (int)
  logic signed [31:0] term1, term2, sum32;
  logic signed [15:0] dT_new_q15;      // Q0.7

  // --- Ograniczenie (clamp) ---
  logic signed [15:0] dmax_q15, clip_hi, clip_lo; // Q0.7

  // --- Konwersja Q0.7 → Q7.0 (kombinacyjnie, bez rejestru pośredniego) ---
  logic signed [15:0] q07_adj_comb;    // Q0.7 po „anty-dryfie”
  logic signed [7:0]  q07_to_s8;       // Q7.0

  // --- Ścieżka kombinacyjna ---
  always_comb begin
    // Limituj k_dt do [0..7], by uniknąć nieprzewidzianych przesunięć
    k_dt_lim = (k_dt > 8'd7) ? 4'd7 : k_dt[3:0];

    // ∆T w Q0.7
    delta_q8     = $signed({{1{T_cur[7]}},  T_cur}) - $signed({{1{T_prev[7]}}, T_prev}); // Q8.0
    delta_q07    = $signed(delta_q8) <<< 7;        // Q8.0 → Q0.7
    delta_scaled = delta_q07 >>> k_dt_lim;         // /2^k (Q0.7)

    // Wagi całkowite (0..256)
    inv_a_u = 16'd256 - {8'b0, alpha};
    a_u     = {8'b0, alpha};

    // EMA: (prev*inv_a + delta*a) / 256  (cała ścieżka w Q0.7)
    term1      = $signed(dT_prev_q15) * $signed(inv_a_u); // Q0.7 * int → 32b
    term2      = $signed(delta_scaled) * $signed(a_u);    // Q0.7 * int → 32b
    sum32      = term1 + term2;
    dT_new_q15 = $signed(sum32 >>> 8);                    // /256 → Q0.7

    // Clamp symetryczny w Q0.7 (D_MAX: Q7.0 → Q0.7)
    dmax_q15 = $signed(d_max) <<< 7;
    clip_hi  = (dT_new_q15 >  dmax_q15) ?  dmax_q15 : dT_new_q15;
    clip_lo  = (clip_hi    < -dmax_q15) ? -dmax_q15 : clip_hi;

    // Anty-dryf i konwersja do Q7.0 — kombinacyjnie (zero-latency)
    q07_adj_comb = (clip_lo < 0) ? (clip_lo + 16'sd127) : clip_lo; // „trunc toward zero” dla <0
    q07_to_s8    = $signed(q07_adj_comb >>> 7);
  end

  // --- Aktualizacja sekwencyjna + INIT ---
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      T_prev       <= '0;
      dT_prev_q15  <= '0;      // Q0.7
      dT_out       <= '0;      // Q7.0
      dt_valid     <= 1'b0;
    end else if (init) begin
      // INIT: wyzeruj EMA i złap bieżące T, bez „spike” na wyjściu
      T_prev       <= T_cur;   // następny delta = 0
      dT_prev_q15  <= '0;      // Q0.7
      dT_out       <= '0;
      dt_valid     <= 1'b0;
    end else begin
      // Zwykły krok EMA
      T_prev       <= T_cur;
      dT_prev_q15  <= clip_lo;     // Q0.7
      dT_out       <= q07_to_s8;   // użyj wartości z TEGO cyklu (bez opóźnienia)
      dt_valid     <= 1'b1;
    end
  end

endmodule
