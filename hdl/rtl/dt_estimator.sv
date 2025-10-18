// dt_estimator.sv — EMA różnicy z saturacją
// REQ: 060,061,062,210

module dt_estimator(
  input  logic       clk, rst_n,
  input  logic signed [7:0] T_cur,      // Q7.0
  input  logic [7:0] alpha,             // ~ALPHA/256
  input  logic [7:0] k_dt,              // 2^k
  input  logic [7:0] d_max,             // Q7.0
  input  logic       init,              // impuls
  output logic signed [7:0] dT_out,     // Q7.0
  output logic       dt_valid
);

  logic signed [7:0]  T_prev;
  logic signed [15:0] dT_prev_q15;

  logic signed [8:0]  delta_q8    = $signed({T_cur[7],T_cur}) - $signed({T_prev[7],T_prev});
  logic signed [15:0] delta_s     = {delta_q8,7'b0};        // *128 -> Q1.15
  logic signed [15:0] delta_scaled= delta_s >>> k_dt;       // /2^k

  logic [15:0] alpha_q = {8'b0, alpha};
  logic [15:0] one_q   = 16'd256;
  logic [15:0] inv_a   = one_q - alpha_q;

  logic signed [31:0] term1 = $signed(dT_prev_q15) * $signed({inv_a,8'b0});
  logic signed [31:0] term2 = $signed(delta_scaled) * $signed({alpha_q,8'b0});
  logic signed [31:0] sum32;
  logic signed [15:0] dT_new_q15;

  logic signed [15:0] dmax_q15 = {d_max,8'd0};
  logic signed [15:0] clip_hi  = (dT_new_q15 >  dmax_q15) ? dmax_q15 : dT_new_q15;
  logic signed [15:0] clip_lo  = (clip_hi    < -dmax_q15) ? -dmax_q15: clip_hi;

  always_comb begin
    sum32 = term1 + term2;
    dT_new_q15 = sum32[31:16];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      T_prev<=0; dT_prev_q15<=0; dT_out<=0; dt_valid<=0;
    end else if (init) begin
      T_prev<=T_cur; dT_prev_q15<=0; dT_out<=0; dt_valid<=0; // REQ-062
    end else begin
      T_prev<=T_cur;
      dT_prev_q15<=clip_lo;
      dT_out<=clip_lo[15:8]; // Q1.15 -> Q7.0
      dt_valid<=1'b1;
    end
  end
endmodule
