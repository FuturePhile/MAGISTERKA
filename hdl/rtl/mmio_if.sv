// mmio_if.sv — MMIO rejestry/sterowanie
// REQ: 110,120,130,062

module mmio_if(
  input  logic       clk, rst_n,
  input  logic       cs, rd, wr,
  input  logic [7:0] addr, wdata,
  output logic [7:0] rdata,

  output logic       start_pulse,
  output logic       init_pulse,
  output logic       reg_mode, dt_mode,

  output logic [7:0] T_reg, dT_reg,
  input  logic [7:0] dT_mon,
  input  logic [7:0] G_out,

  // MF T
  output logic [7:0] T_neg_a, T_neg_b, T_neg_c, T_neg_d,
  output logic [7:0] T_zero_a, T_zero_b, T_zero_c, T_zero_d,
  output logic [7:0] T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d,
  // MF dT
  output logic [7:0] dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d,
  output logic [7:0] dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d,
  output logic [7:0] dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d,

  // singletony
  output logic [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22,

  // estymator
  output logic [7:0] alpha, k_dt, d_max,

  input  logic       busy, valid
);

  // --- start/init: detekcja zbocza na zapisie bitu ---
  logic start_d, init_d;
  wire  wr_ctrl = (cs && wr && addr==8'h01);

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin start_d<=0; init_d<=0; end
    else begin
      start_d <= wr_ctrl && wdata[0];
      init_d  <= wr_ctrl && wdata[3];
    end
  end

  always_comb begin
    start_pulse = (wr_ctrl && wdata[0] && !start_d);
    init_pulse  = (wr_ctrl && wdata[3] && !init_d);
  end

  // --- reset/seed wartości (REQ-120) + zapisy ---
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      reg_mode<=1'b0; dt_mode<=1'b1; T_reg<=0; dT_reg<=0;
      {g00,g01,g02,g10,g11,g12,g20,g21,g22} <= '{8'd100,8'd50,8'd30,8'd50,8'd50,8'd50,8'd80,8'd50,8'd0};
      alpha<=8'd32; k_dt<=8'd3; d_max<=8'd64;
      // TODO: MF domyślne
    end else if (cs && wr) begin
      unique case (addr)
        8'h01: begin reg_mode <= wdata[1]; dt_mode <= wdata[2]; end
        8'h02:       T_reg    <= wdata;
        8'h03: if(!dt_mode)   dT_reg   <= wdata;
        // singletony:
        8'h30: g00<=wdata; 8'h31: g01<=wdata; 8'h32: g02<=wdata;
        8'h33: g10<=wdata; 8'h34: g11<=wdata; 8'h35: g12<=wdata;
        8'h36: g20<=wdata; 8'h37: g21<=wdata; 8'h38: g22<=wdata;
        // estymator:
        8'h40: alpha<=wdata; 8'h41: k_dt<=wdata; 8'h42: d_max<=wdata;
        // 0x10..0x27 — MF T/dT: TODO a,b,c,d według mapy
        default: ;
      endcase
    end
  end

  // --- odczyty ---
  always_comb begin
    rdata = 8'h00;
    if (cs && rd) begin
      unique case (addr)
        8'h00: rdata = {6'b0, valid, busy};                                   // STATUS
        8'h01: rdata = {4'b0, 1'b0, dt_mode, reg_mode, 1'b0};                  // CTRL (rd)
        8'h02: rdata = T_reg;
        8'h03: rdata = dt_mode ? dT_mon : dT_reg;
        8'h04: rdata = G_out;
        8'h40: rdata = alpha; 8'h41: rdata = k_dt; 8'h42: rdata = d_max;
        default: rdata = 8'h00;
      endcase
    end
  end

endmodule
