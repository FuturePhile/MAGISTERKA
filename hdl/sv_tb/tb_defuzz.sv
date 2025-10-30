// tb_defuzz_req050.sv - lightweight TB for defuzz.sv
// REQ-050: G = (S_wg / max(S_w, EPS)) * 100, rounded/truncated as in DUT, safe for S_w≈0
// REQ-210: inputs Q1.15; output 0..100 (uint8); check saturation and reset behavior
// Style: module -> signals -> DUT -> helpers -> initial/always

`timescale 1ns/1ps
module tb_defuzz_req050;
  timeunit 1ns;
  timeprecision 1ps;

  // DUT I/O
  logic        clk;
  logic        rst_n;
  logic [15:0] S_w;      // Q1.15
  logic [15:0] S_wg;     // Q1.15
  logic  [7:0] G_out;

  // TB control
  bit verbose;
  integer i;

  // DUT instantiation
  defuzz dut (
    .clk(clk),
    .rst_n(rst_n),
    .S_w(S_w),
    .S_wg(S_wg),
    .G_out(G_out)
  );

  // Clock / Reset
  localparam real TCLK_NS = 10.0;

  initial begin
    clk = 1'b0;
    forever #(TCLK_NS/2.0) clk = ~clk;
  end

  // Reference model (bit-accurate to DUT implementation)
  function automatic [7:0] ref_defuzz(
    input logic [15:0] sw_q15,
    input logic [15:0] swg_q15
  );
    localparam logic [15:0] EPS = 16'd1;
    logic [15:0] den_q15;
    logic [31:0] ratio_q15;   // Q1.15
    logic [31:0] percent_u;   // integer percent before clamp
    logic  [7:0] sat_u8;
    begin
      den_q15   = (sw_q15 < EPS) ? EPS : sw_q15;
      ratio_q15 = ({16'd0, swg_q15} << 15) / den_q15;        // trunc
      percent_u = (ratio_q15 * 32'd100) >> 15;               // trunc
      sat_u8    = (percent_u > 32'd100) ? 8'd100 : percent_u[7:0];
      return sat_u8;
    end
  endfunction

  // Helpers
  task automatic apply_and_check(
    input logic [15:0] sw,
    input logic [15:0] swg,
    input string       tag
  );
    logic [7:0] expG;
    begin
      @(negedge clk);
      S_w  = sw;
      S_wg = swg;
      expG = ref_defuzz(sw, swg);

      @(posedge clk);
      #1ps;

      if (G_out !== expG) $error("[REQ-050] %s mismatch G_out=%0d exp=%0d (S_w=%0d S_wg=%0d)", tag, G_out, expG, sw, swg);
      if (verbose) $display("INFO: [REQ-050] %s S_w=%0d S_wg=%0d -> G=%0d", tag, sw, swg, G_out);
    end
  endtask

  // Test flow
  initial begin
    verbose = $test$plusargs("verbose");

    // Reset
    rst_n = 1'b0;
    S_w   = '0;
    S_wg  = '0;
    repeat (2) @(posedge clk);
    assert (G_out == 8'd0) else $error("[REQ-050] PoR G_out!=0");
    rst_n = 1'b1;

    // Case A: zero sums -> expect 0 (epsilon path but numerator is 0)
    apply_and_check(16'd0, 16'd0, "A1 zeros");

    // Case B: nominal ratios
    apply_and_check(16'd32767, 16'd16384, "B1 0.5 -> 50%");
    apply_and_check(16'd32767, 16'd32767, "B2 1.0 -> 100%");
    apply_and_check(16'd20000, 16'd10000, "B3 0.5 -> 50%");

    // Case C: truncation edges (DUT truncs)
    apply_and_check(16'd30000, 16'd14999, "C1 ~49% trunc");
    apply_and_check(16'd30000, 16'd15000, "C2 ~50% trunc");

    // Case D: saturation above 100%
    apply_and_check(16'd10000, 16'd30000, "D1 >100% -> clamp 100");

    // Case E: tiny denominator
    apply_and_check(16'd1, 16'd32767, "E1 small den, big num -> 100");
    apply_and_check(16'd1, 16'd0,     "E2 small den, zero num -> 0");

    // Case F: random sanity (S_wg <= S_w to avoid trivial clamps)
    for (i = 0; i < 20; i = i + 1) begin
      logic [15:0] rSw;
      logic [15:0] rSwg;
      rSw  = $urandom_range(0, 32767);
      rSwg = $urandom_range(0, rSw);
      apply_and_check(rSw, rSwg, "F rand");
    end

    $display("[REQ-050][REQ-210] defuzz TB finished");
    $finish;
  end

endmodule
