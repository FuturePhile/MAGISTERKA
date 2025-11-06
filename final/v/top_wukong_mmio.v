// top_wukong.v - Wukong (XC7A100T) + RPi Pico (parallel interface)

module top_wukong (
  input  wire        clk,
  input  wire        rst_n,

  // --- Pico bus ---
  input  wire        cs_i,
  input  wire        wr_i,
  input  wire        rd_i,
  input  wire [5:0]  a_i,
  input  wire [7:0]  d_w_i,
  output reg  [7:0]  d_r_o,
  output reg         rdy_o,

  output wire        LED_CLK_PIN,
  output wire        LED_RDY_PIN
);

wire clk20, locked, core_rst_n;

clk_wiz_0 clk_div_20
(
  .clk_out1(clk20),
  .resetn(rst_n),
  .locked(locked),
  .clk_in1(clk)
);

assign core_rst_n = rst_n & locked;

// === 1) CDC for inputs ===
reg [2:0] cs_s, wr_s, rd_s;
always @(posedge clk20 or negedge core_rst_n) begin
  if(!core_rst_n) begin cs_s<=0; wr_s<=0; rd_s<=0; end
  else begin
    cs_s <= {cs_s[1:0], cs_i};
    wr_s <= {wr_s[1:0], wr_i};
    rd_s <= {rd_s[1:0], rd_i};
  end
end
wire cs = cs_s[2];
wire wr = wr_s[2];
wire rd = rd_s[2];

reg wr_d, rd_d;
always @(posedge clk20 or negedge core_rst_n) begin
  if(!core_rst_n) begin wr_d<=0; rd_d<=0; end
  else begin wr_d<=wr; rd_d<=rd; end
end
wire wr_rise = cs & ( wr & ~wr_d);
wire rd_rise = cs & ( rd & ~rd_d);
wire rd_fall = cs & (~rd &  rd_d);

// === 2) MMIO signals ===
reg        cs_mm, rd_mm, wr_mm;
reg [7:0]  wdata;
wire [7:0] rdata;
reg [7:0]  addr8;
reg        rd_active;

always @(posedge clk20 or negedge core_rst_n) begin
  if(!core_rst_n) begin
    cs_mm<=1'b0; rd_mm<=1'b0; wr_mm<=1'b0;
    addr8<=8'h00; wdata<=8'h00; rd_active<=1'b0;
  end else begin
    cs_mm <= cs;

    wr_mm <= 1'b0;
    if (wr_rise) begin
      addr8 <= {3'b000, a_i};
      wdata <= d_w_i;
      wr_mm <= 1'b1;
    end

    rd_mm <= rd;

    if (rd_rise) begin
      addr8     <= {3'b000, a_i};
      rd_active <= 1'b1;
    end else if (rd_active) begin
      rd_active <= 1'b0;
    end

    if (rd_fall || !cs) rd_active <= 1'b0;
  end
end

// === 3) Core + debug ===
wire        start, init, reg_mode, dt_mode, valid;
wire  [7:0] G_out;
wire signed [7:0]
  T_in, dT_in,
  T_neg_a, T_neg_b, T_neg_c, T_neg_d,
  T_zero_a, T_zero_b, T_zero_c, T_zero_d,
  T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d,
  dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d,
  dT_zero_a,dT_zero_b,dT_zero_c,dT_zero_d,
  dT_pos_a, dT_pos_b, dT_pos_c, dT_pos_d;

wire [15:0] dbg_S_w, dbg_S_wg;
wire [7:0]  dbg_G_q;
wire [7:0]  dbg_dT_sel;

mmio_if u_mmio_if (
  .clk(clk20), .rst_n(core_rst_n),
  .cs(cs_mm), .rd(rd_mm), .wr(wr_mm),
  .addr(addr8),
  .wdata(wdata),
  .rdata(rdata),
  .start(start), .init(init),
  .reg_mode(reg_mode), .dt_mode(dt_mode),
  .T_in(T_in), .dT_in(dT_in),
  .T_neg_a(T_neg_a), .T_neg_b(T_neg_b), .T_neg_c(T_neg_c), .T_neg_d(T_neg_d),
  .T_zero_a(T_zero_a), .T_zero_b(T_zero_b), .T_zero_c(T_zero_c), .T_zero_d(T_zero_d),
  .T_pos_a(T_pos_a), .T_pos_b(T_pos_b), .T_pos_c(T_pos_c), .T_pos_d(T_pos_d),
  .dT_neg_a(dT_neg_a), .dT_neg_b(dT_neg_b), .dT_neg_c(dT_neg_c), .dT_neg_d(dT_neg_d),
  .dT_zero_a(dT_zero_a), .dT_zero_b(dT_zero_b), .dT_zero_c(dT_zero_c), .dT_zero_d(dT_zero_d),
  .dT_pos_a(dT_pos_a), .dT_pos_b(dT_pos_b), .dT_pos_c(dT_pos_c), .dT_pos_d(dT_pos_d),
  .valid(valid), .G_out(G_out),

  // debug inputs mapped to RO
  .dbg_S_w(dbg_S_w),
  .dbg_S_wg(dbg_S_wg),
  .dbg_G_q(dbg_G_q),
  .dbg_dT_sel(dbg_dT_sel)
);

top_coprocessor u_top_coprocessor (
  .clk(clk20), .rst_n(core_rst_n),
  .start(start), .init(init),
  .reg_mode(reg_mode), .dt_mode(dt_mode),
  .T_in(T_in), .dT_in(dT_in),
  .T_neg_a(T_neg_a), .T_neg_b(T_neg_b), .T_neg_c(T_neg_c), .T_neg_d(T_neg_d),
  .T_zero_a(T_zero_a), .T_zero_b(T_zero_b), .T_zero_c(T_zero_c), .T_zero_d(T_zero_d),
  .T_pos_a(T_pos_a), .T_pos_b(T_pos_b), .T_pos_c(T_pos_c), .T_pos_d(T_pos_d),
  .dT_neg_a(dT_neg_a), .dT_neg_b(dT_neg_b), .dT_neg_c(dT_neg_c), .dT_neg_d(dT_neg_d),
  .dT_zero_a(T_zero_a), .dT_zero_b(T_zero_b), .dT_zero_c(T_zero_c), .dT_zero_d(T_zero_d),
  .dT_pos_a(dT_pos_a), .dT_pos_b(dT_pos_b), .dT_pos_c(dT_pos_c), .dT_pos_d(dT_pos_d),
  .valid(valid), .G_out(G_out),

  // debug outputs
  .dbg_S_w(dbg_S_w),
  .dbg_S_wg(dbg_S_wg),
  .dbg_G_q(dbg_G_q),
  .dbg_dT_sel(dbg_dT_sel)
);

// === 4) 1T read latency and level RDY ===
reg rd_pipe, rd_ready;
always @(posedge clk20 or negedge core_rst_n) begin
  if(!core_rst_n) begin
    d_r_o   <= 8'h00;
    rd_pipe <= 1'b0;
    rd_ready<= 1'b0;
    rdy_o   <= 1'b0;
  end else begin
    rdy_o <= rd_ready;
    if (rd_rise) begin
      rd_pipe  <= 1'b1;
      rd_ready <= 1'b0;
    end else if (rd_pipe) begin
      d_r_o    <= rdata;
      rd_ready <= 1'b1;
      rd_pipe  <= 1'b0;
    end
    if (rd_fall || !cs) rd_ready <= 1'b0;
  end
end

// --- LED heartbeat ---
reg [24:0] hb_cnt;
always @(posedge clk20 or negedge core_rst_n) begin
  if(!core_rst_n) hb_cnt <= 0;
  else            hb_cnt <= hb_cnt + 1'b1;
end
assign LED_CLK_PIN = hb_cnt[24];
assign LED_RDY_PIN = rdy_o;

endmodule
