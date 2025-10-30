// mmio_if.v - register shadow for MCU (8-bit bus) <-> top_coprocessor (core)
//
// RO:
//   0x00 STATUS: {7'b0, valid}
//   0x04 G: 0..100
// WO:
//   0x01 CTRL: [3]=INIT (W1P), [2]=DT_MODE, [1]=REG_MODE, [0]=START (W1P)
//   0x02 T (Q7.0), 0x03 dT (Q7.0; ignored when DT_MODE=1)
//   0x10..0x1B: T thresholds (a,b,c,d) for {neg,zero,pos}
//   0x1C..0x27: dT thresholds (a,b,c,d) for {neg,zero,pos}
module mmio_if (
  input         clk,
  input         rst_n,
  input         cs,
  input         rd,
  input         wr,
  input   [7:0] addr,
  input   [7:0] wdata,
  output reg [7:0] rdata,
  output        start,        // one-cycle level (core edge-detects)
  output        init,         // one-cycle level (core edge-detects)
  output reg    reg_mode,
  output reg    dt_mode,
  output reg signed [7:0] T_in,
  output reg signed [7:0] dT_in,
  output reg signed [7:0] T_neg_a,
  output reg signed [7:0] T_neg_b,
  output reg signed [7:0] T_neg_c,
  output reg signed [7:0] T_neg_d,
  output reg signed [7:0] T_zero_a,
  output reg signed [7:0] T_zero_b,
  output reg signed [7:0] T_zero_c,
  output reg signed [7:0] T_zero_d,
  output reg signed [7:0] T_pos_a,
  output reg signed [7:0] T_pos_b,
  output reg signed [7:0] T_pos_c,
  output reg signed [7:0] T_pos_d,
  output reg signed [7:0] dT_neg_a,
  output reg signed [7:0] dT_neg_b,
  output reg signed [7:0] dT_neg_c,
  output reg signed [7:0] dT_neg_d,
  output reg signed [7:0] dT_zero_a,
  output reg signed [7:0] dT_zero_b,
  output reg signed [7:0] dT_zero_c,
  output reg signed [7:0] dT_zero_d,
  output reg signed [7:0] dT_pos_a,
  output reg signed [7:0] dT_pos_b,
  output reg signed [7:0] dT_pos_c,
  output reg signed [7:0] dT_pos_d,
  input         valid,
  input   [7:0] G_out
);

  // Internal one-cycle strobes (only these are registered)
  reg start_w1;
  reg init_w1;

  // Register file and write-one-pulse generation
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_mode  <= 1'b1;      // 9-rule
      dt_mode   <= 1'b1;      // internal dT
      T_in      <= 8'sd0;
      dT_in     <= 8'sd0;

      T_neg_a   <= 8'h80;
      T_neg_b   <= 8'h80;
      T_neg_c   <= 8'hC0;
      T_neg_d   <= 8'h00;
      T_zero_a  <= 8'hC0;
      T_zero_b  <= 8'h00;
      T_zero_c  <= 8'h00;
      T_zero_d  <= 8'h40;
      T_pos_a   <= 8'h00;
      T_pos_b   <= 8'h40;
      T_pos_c   <= 8'h80;
      T_pos_d   <= 8'h80;

      dT_neg_a  <= 8'h80;
      dT_neg_b  <= 8'h80;
      dT_neg_c  <= 8'hC0;
      dT_neg_d  <= 8'h00;
      dT_zero_a <= 8'hC0;
      dT_zero_b <= 8'h00;
      dT_zero_c <= 8'h00;
      dT_zero_d <= 8'h40;
      dT_pos_a  <= 8'h00;
      dT_pos_b  <= 8'h40;
      dT_pos_c  <= 8'h80;
      dT_pos_d  <= 8'h80;

      start_w1  <= 1'b0;
      init_w1   <= 1'b0;
    end else begin
      // default: clear one-cycle pulses
      start_w1  <= 1'b0;
      init_w1   <= 1'b0;

      if (cs && wr) begin
        case (addr)
          8'h01: begin
            // CTRL: pulse bits asserted for one cycle
            start_w1 <= wdata[0];
            init_w1  <= wdata[3];
            reg_mode <= wdata[1];
            dt_mode  <= wdata[2];
          end
          8'h02: T_in <= wdata;
          8'h03: if (!dt_mode) dT_in <= wdata;

          // T thresholds (WO)
          8'h10: T_neg_a  <= wdata;
          8'h11: T_neg_b  <= wdata;
          8'h12: T_neg_c  <= wdata;
          8'h13: T_neg_d  <= wdata;
          8'h14: T_zero_a <= wdata;
          8'h15: T_zero_b <= wdata;
          8'h16: T_zero_c <= wdata;
          8'h17: T_zero_d <= wdata;
          8'h18: T_pos_a  <= wdata;
          8'h19: T_pos_b  <= wdata;
          8'h1A: T_pos_c  <= wdata;
          8'h1B: T_pos_d  <= wdata;

          // dT thresholds (WO)
          8'h1C: dT_neg_a  <= wdata;
          8'h1D: dT_neg_b  <= wdata;
          8'h1E: dT_neg_c  <= wdata;
          8'h1F: dT_neg_d  <= wdata;
          8'h20: dT_zero_a <= wdata;
          8'h21: dT_zero_b <= wdata;
          8'h22: dT_zero_c <= wdata;
          8'h23: dT_zero_d <= wdata;
          8'h24: dT_pos_a  <= wdata;
          8'h25: dT_pos_b  <= wdata;
          8'h26: dT_pos_c  <= wdata;
          8'h27: dT_pos_d  <= wdata;

          default: /* no-op */;
        endcase
      end
    end
  end

  // Single drivers for start and init
  assign start = start_w1;
  assign init  = init_w1;

  // Read-only path
  always @(*) begin
    rdata = 8'h00;
    if (cs && rd) begin
      case (addr)
        8'h00: rdata = {7'b0, valid};
        8'h04: rdata = G_out;
        default: rdata = 8'h00;
      endcase
    end
  end

endmodule
