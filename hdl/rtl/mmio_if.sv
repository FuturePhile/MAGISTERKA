// mmio_if.sv — register shadow for MCU (8-bit bus) <-> top_coprocessor (direct I/O)
//
// RO:
//   0x00 STATUS: {7'b0, valid}
//   0x04 G:       0..100
// WO:
//   0x01 CTRL: [3]=INIT (W1P level 1-cycle), [2]=DT_MODE, [1]=REG_MODE, [0]=START (W1P level 1-cycle)
//   0x02 T (Q7.0), 0x03 dT (Q7.0; ignored when DT_MODE=1)
//   0x10..0x1B: T thresholds (a,b,c,d) for {neg,zero,pos}
//   0x1C..0x27: dT thresholds (a,b,c,d) for {neg,zero,pos}

module mmio_if (
  input  logic       clk,
  input  logic       rst_n,

  input  logic       cs,
  input  logic       rd,
  input  logic       wr,
  input  logic [7:0] addr,
  input  logic [7:0] wdata,
  output logic [7:0] rdata,

  // to core
  output logic       start,
  output logic       init,
  output logic       reg_mode,
  output logic       dt_mode,
  output logic signed [7:0] T_in,
  output logic signed [7:0] dT_in,
  output logic signed [7:0] T_neg_a, T_neg_b, T_neg_c, T_neg_d,
  output logic signed [7:0] T_zero_a, T_zero_b, T_zero_c, T_zero_d,
  output logic signed [7:0] T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d,
  output logic signed [7:0] dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d,
  output logic signed [7:0] dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d,
  output logic signed [7:0] dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d,

  // from core
  input  logic       valid,
  input  logic [7:0] G_out
);

  logic start_w1, init_w1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start    <= 1'b0;
      init     <= 1'b0;
      reg_mode <= 1'b1; // default 9 rules
      dt_mode  <= 1'b1; // default internal dT
      T_in     <= '0;
      dT_in    <= '0;

      T_neg_a<=8'h80; T_neg_b<=8'h80; T_neg_c<=8'hC0; T_neg_d<=8'h00;
      T_zero_a<=8'hC0; T_zero_b<=8'h00; T_zero_c<=8'h00; T_zero_d<=8'h40;
      T_pos_a<=8'h00;  T_pos_b<=8'h40; T_pos_c<=8'h80; T_pos_d<=8'h80;

      dT_neg_a<=8'h80; dT_neg_b<=8'h80; dT_neg_c<=8'hC0; dT_neg_d<=8'h00;
      dT_zero_a<=8'hC0; dT_zero_b<=8'h00; dT_zero_c<=8'h00; dT_zero_d<=8'h40;
      dT_pos_a<=8'h00;  dT_pos_b<=8'h40; dT_pos_c<=8'h80; dT_pos_d<=8'h80;

      start_w1 <= 1'b0;
      init_w1  <= 1'b0;
    end
    else if (cs && wr) begin
      unique case (addr)
        8'h01: begin
          start_w1 <= wdata[0];
          init_w1  <= wdata[3];
          reg_mode <= wdata[1];
          dt_mode  <= wdata[2];
        end
        8'h02: T_in  <= wdata;
        8'h03: if (!dt_mode) dT_in <= wdata;

        8'h10: T_neg_a  <= wdata;  8'h11: T_neg_b  <= wdata;
        8'h12: T_neg_c  <= wdata;  8'h13: T_neg_d  <= wdata;
        8'h14: T_zero_a <= wdata;  8'h15: T_zero_b <= wdata;
        8'h16: T_zero_c <= wdata;  8'h17: T_zero_d <= wdata;
        8'h18: T_pos_a  <= wdata;  8'h19: T_pos_b  <= wdata;
        8'h1A: T_pos_c  <= wdata;  8'h1B: T_pos_d  <= wdata;

        8'h1C: dT_neg_a  <= wdata; 8'h1D: dT_neg_b  <= wdata;
        8'h1E: dT_neg_c  <= wdata; 8'h1F: dT_neg_d  <= wdata;
        8'h20: dT_zero_a <= wdata; 8'h21: dT_zero_b <= wdata;
        8'h22: dT_zero_c <= wdata; 8'h23: dT_zero_d <= wdata;
        8'h24: dT_pos_a  <= wdata; 8'h25: dT_pos_b  <= wdata;
        8'h26: dT_pos_c  <= wdata; 8'h27: dT_pos_d  <= wdata;

        default: /* no-op */;
      endcase
    end
    else begin
      // clear one-cycle control levels
      start_w1 <= 1'b0;
      init_w1  <= 1'b0;
    end
  end

  // expose the one-cycle control levels to the core
  always_comb begin
    start = start_w1;
    init  = init_w1;
  end

  // RO path
  always_comb begin
    rdata = 8'h00;
    if (cs && rd) begin
      unique case (addr)
        8'h00: rdata = {7'b0, valid};
        8'h04: rdata = G_out;
        default: rdata = 8'h00;
      endcase
    end
  end

endmodule
