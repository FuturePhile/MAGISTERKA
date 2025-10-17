//------------------------------------------------------------------------------
// mmio_if.sv -- rejestry i szyna 8-bit MMIO (REQ-110/120)
// Uproszczony interfejs: cs, wr, rd, addr[7:0], wdata[7:0], rdata[7:0]
//------------------------------------------------------------------------------
module mmio_if (
  input  logic        clk,
  input  logic        rst,

  input  logic        cs,
  input  logic        wr,
  input  logic        rd,
  input  logic [7:0]  addr,
  input  logic [7:0]  wdata,
  output logic [7:0]  rdata,

  // sygnały do datapathu
  output logic        start_pulse,
  output logic        reg_mode,    // 0:4 reg, 1:9 reg
  output logic        dt_mode,     // 0:ext, 1:int
  output logic        init_pulse,

  output logic signed [7:0] T_reg,
  output logic signed [7:0] dT_reg,

  // MF paramy (tylko przykładowo dla T_neg; pozostałe analogicznie)
  output logic signed [7:0] Tn_a, Tn_b, Tn_c, Tn_d,
  output logic signed [7:0] Tz_a, Tz_b, Tz_c, Tz_d,
  output logic signed [7:0] Tp_a, Tp_b, Tp_c, Tp_d,
  output logic signed [7:0] dTn_a, dTn_b, dTn_c, dTn_d,
  output logic signed [7:0] dTz_a, dTz_b, dTz_c, dTz_d,
  output logic signed [7:0] dTp_a, dTp_b, dTp_c, dTp_d,

  // singletons
  output logic [7:0] g_00, g_01, g_02, g_10, g_11, g_12, g_20, g_21, g_22,

  // estymator
  output logic [7:0] ALPHA, K_DT,
  output logic signed [7:0] D_MAX,

  // status z datapathu
  input  logic        busy,
  input  logic        valid,
  input  logic signed [7:0] dT_live,
  input  logic [7:0]  G_out
);
  // Rejestr CTRL
  logic start, reg_mode_r, dt_mode_r, init;
  assign reg_mode = reg_mode_r;
  assign dt_mode  = dt_mode_r;

  // Auto-clear start/init na 1 cykl
  always_ff @(posedge clk) begin
    if (rst) begin
      start <= 0; init <= 0; reg_mode_r <= 1'b0; dt_mode_r <= 1'b1;
    end else begin
      start <= 0;
      init  <= 0;
      if (cs && wr && addr==8'h01) begin
        start      <= wdata[0];
        reg_mode_r <= wdata[1];
        dt_mode_r  <= wdata[2];
        init       <= wdata[3];
      end
    end
  end
  assign start_pulse = start;
  assign init_pulse  = init;

  // Proste banki rejestrów (pokażę kilka; resztę uzupełnisz analogicznie)
  always_ff @(posedge clk) begin
    if (rst) begin
      T_reg   <= '0;
      dT_reg  <= '0;
      {Tn_a,Tn_b,Tn_c,Tn_d} <= '{-128,-128,-16,-4};
      {Tz_a,Tz_b,Tz_c,Tz_d} <= '{-16,0,0,16};
      {Tp_a,Tp_b,Tp_c,Tp_d} <= '{  4,16,127,127};
      {dTn_a,dTn_b,dTn_c,dTn_d} <= '{-128,-64,-8,0};
      {dTz_a,dTz_b,dTz_c,dTz_d} <= '{-8,0,0,8};
      {dTp_a,dTp_b,dTp_c,dTp_d} <= '{0,8,64,127};
      {g_00,g_01,g_02,g_10,g_11,g_12,g_20,g_21,g_22} <= '{100,50,30,50,50,50,80,50,0};
      ALPHA <= 8'd32; K_DT <= 8'd3; D_MAX <= 8'd64;
    end else if (cs && wr) begin
      unique case (addr)
        8'h02: T_reg  <= wdata;
        8'h03: if (!dt_mode_r) dT_reg <= wdata;
        // MF T_neg
        8'h10: Tn_a <= wdata;  8'h11: Tn_b <= wdata;
        8'h12: Tn_c <= wdata;  8'h13: Tn_d <= wdata;
        // MF T_zero
        8'h14: Tz_a <= wdata;  8'h15: Tz_b <= wdata;
        8'h16: Tz_c <= wdata;  8'h17: Tz_d <= wdata;
        // MF T_pos
        8'h18: Tp_a <= wdata;  8'h19: Tp_b <= wdata;
        8'h1A: Tp_c <= wdata;  8'h1B: Tp_d <= wdata;
        // MF dT_neg
        8'h1C: dTn_a <= wdata; 8'h1D: dTn_b <= wdata;
        8'h1E: dTn_c <= wdata; 8'h1F: dTn_d <= wdata;
        // MF dT_zero
        8'h20: dTz_a <= wdata; 8'h21: dTz_b <= wdata;
        8'h22: dTz_c <= wdata; 8'h23: dTz_d <= wdata;
        // MF dT_pos
        8'h24: dTp_a <= wdata; 8'h25: dTp_b <= wdata;
        8'h26: dTp_c <= wdata; 8'h27: dTp_d <= wdata;
        // singletony
        8'h30: g_00 <= wdata;  8'h31: g_01 <= wdata;  8'h32: g_02 <= wdata;
        8'h33: g_10 <= wdata;  8'h34: g_11 <= wdata;  8'h35: g_12 <= wdata;
        8'h36: g_20 <= wdata;  8'h37: g_21 <= wdata;  8'h38: g_22 <= wdata;
        // estymator
        8'h40: ALPHA <= wdata; 8'h41: K_DT <= wdata; 8'h42: D_MAX <= wdata;
      endcase
    end
  end

  // Odczyty
  always_comb begin
    rdata = 8'h00;
    if (cs && rd) begin
      unique case (addr)
        8'h00: rdata = {6'd0, valid, busy};
        8'h01: rdata = {4'd0, 1'b0, dt_mode_r, reg_mode_r, 1'b0}; // INIT/START odczyt jako 0
        8'h02: rdata = T_reg;
        8'h03: rdata = (dt_mode_r) ? dT_live : dT_reg;
        8'h04: rdata = G_out;
        default: rdata = 8'h00; // uzupełnij wg mapy
      endcase
    end
  end
endmodule
