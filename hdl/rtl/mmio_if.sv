// mmio_if.sv — MMIO register map and control
// REQ-110: bus & base registers; REQ-120: address map; REQ-130: polling (no IRQ)
// REQ-062: INIT pulse generation

module mmio_if (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       cs,
  input  logic       rd,
  input  logic       wr,
  input  logic [7:0] addr,
  input  logic [7:0] wdata,
  output logic [7:0] rdata,

  // control
  output logic       start_pulse,
  output logic       init_pulse,
  output logic       reg_mode,    // 0: 4 rules, 1: 9 rules
  output logic       dt_mode,     // 0: external dT, 1: internal estimator

  // data
  output logic [7:0] T_reg,
  output logic [7:0] dT_reg,
  input  logic [7:0] dT_mon,      // readback when dt_mode=1
  input  logic [7:0] G_out,       // result (0..100)

  // MFs for T
  output logic [7:0] T_neg_a, T_neg_b, T_neg_c, T_neg_d,
  output logic [7:0] T_zero_a, T_zero_b, T_zero_c, T_zero_d,
  output logic [7:0] T_pos_a,  T_pos_b,  T_pos_c,  T_pos_d,
  // MFs for dT
  output logic [7:0] dT_neg_a, dT_neg_b, dT_neg_c, dT_neg_d,
  output logic [7:0] dT_zero_a, dT_zero_b, dT_zero_c, dT_zero_d,
  output logic [7:0] dT_pos_a,  dT_pos_b,  dT_pos_c,  dT_pos_d,

  // singletons (percent)
  output logic [7:0] g00, g01, g02, g10, g11, g12, g20, g21, g22,

  // estimator params
  output logic [7:0] alpha,
  output logic [7:0] k_dt,
  output logic [7:0] d_max,

  // status in
  input  logic       busy,
  input  logic       valid
);
  // --- start/init edge detection (one-cycle pulses) ---
  logic start_d, init_d;
  logic wr_ctrl;

  assign wr_ctrl = (cs && wr && (addr == 8'h01));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_d <= 1'b0;
      init_d  <= 1'b0;
    end else begin
      start_d <= (wr_ctrl && wdata[0]);
      init_d  <= (wr_ctrl && wdata[3]);
    end
  end

  always_comb begin
    start_pulse = (wr_ctrl && wdata[0] && !start_d);
    init_pulse  = (wr_ctrl && wdata[3] && !init_d);
  end

  // --- registers write path (defaults + writes) ---
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // defaults per REQ-120
      reg_mode <= 1'b1;          // default to 9 rules (you can change)
      dt_mode  <= 1'b1;          // default to internal dT
      T_reg    <= 8'd0;
      dT_reg   <= 8'd0;
      // singleton seeds (example HVAC-ish; adjust in doc if needed)
      g00<=8'd100; g01<=8'd50; g02<=8'd30;
      g10<=8'd50;  g11<=8'd50; g12<=8'd50;
      g20<=8'd80;  g21<=8'd50; g22<=8'd0;
      // estimator params
      alpha<=8'd32; k_dt<=8'd3; d_max<=8'd64;
      // MF defaults (simple symmetric example; TODO: set your final seeds)
      T_neg_a<=8'h80; T_neg_b<=8'h80; T_neg_c<=8'hC0; T_neg_d<=8'h00;
      T_zero_a<=8'hC0; T_zero_b<=8'h00; T_zero_c<=8'h00; T_zero_d<=8'h40;
      T_pos_a<=8'h00;  T_pos_b<=8'h40; T_pos_c<=8'h80; T_pos_d<=8'h80;

      dT_neg_a<=8'h80; dT_neg_b<=8'h80; dT_neg_c<=8'hC0; dT_neg_d<=8'h00;
      dT_zero_a<=8'hC0; dT_zero_b<=8'h00; dT_zero_c<=8'h00; dT_zero_d<=8'h40;
      dT_pos_a<=8'h00;  dT_pos_b<=8'h40; dT_pos_c<=8'h80; dT_pos_d<=8'h80;
    end
    else if (cs && wr) begin
      unique case (addr)
        8'h01: begin
          // CTRL: [0]=start (pulse), [1]=REG_MODE, [2]=DT_MODE, [3]=INIT (pulse)
          reg_mode <= wdata[1];
          dt_mode  <= wdata[2];
        end
        8'h02: T_reg  <= wdata;
        8'h03: if (!dt_mode) dT_reg <= wdata; // ignore write in internal dT mode
        // MF T (a,b,c,d) and dT (a,b,c,d) — fill per your map; examples:

        8'h10: rdata = T_neg_a;   8'h11: rdata = T_neg_b;
        8'h12: rdata = T_neg_c;   8'h13: rdata = T_neg_d;
        8'h14: rdata = T_zero_a;  8'h15: rdata = T_zero_b;
        8'h16: rdata = T_zero_c;  8'h17: rdata = T_zero_d;
        8'h18: rdata = T_pos_a;   8'h19: rdata = T_pos_b;
        8'h1A: rdata = T_pos_c;   8'h1B: rdata = T_pos_d;

        // MF dT
        8'h1C: rdata = dT_neg_a;  8'h1D: rdata = dT_neg_b;
        8'h1E: rdata = dT_neg_c;  8'h1F: rdata = dT_neg_d;
        8'h20: rdata = dT_zero_a; 8'h21: rdata = dT_zero_b;
        8'h22: rdata = dT_zero_c; 8'h23: rdata = dT_zero_d;
        8'h24: rdata = dT_pos_a;  8'h25: rdata = dT_pos_b;
        8'h26: rdata = dT_pos_c;  8'h27: rdata = dT_pos_d;


        // singletons g_ij
        8'h30: g00 <= wdata; 8'h31: g01 <= wdata; 8'h32: g02 <= wdata;
        8'h33: g10 <= wdata; 8'h34: g11 <= wdata; 8'h35: g12 <= wdata;
        8'h36: g20 <= wdata; 8'h37: g21 <= wdata; 8'h38: g22 <= wdata;

        // estimator params
        8'h40: alpha <= wdata; 8'h41: k_dt <= wdata; 8'h42: d_max <= wdata;

        default: /* reserved */ ;
      endcase
    end
  end

  // --- readback path ---
  always_comb begin
    rdata = 8'h00;
    if (cs && rd) begin
      unique case (addr)
        8'h00: rdata = {6'b0, valid, busy}; // STATUS
        8'h01: rdata = {4'b0, 1'b0 /*INIT rd*/, dt_mode, reg_mode, 1'b0 /*start rd*/};
        8'h02: rdata = T_reg;
        8'h03: rdata = dt_mode ? dT_mon : dT_reg;
        8'h04: rdata = G_out;
        // (optional) expose MF and g_ij readback if desired:
        8'h30: rdata = g00; 8'h31: rdata = g01; 8'h32: rdata = g02;
        8'h33: rdata = g10; 8'h34: rdata = g11; 8'h35: rdata = g12;
        8'h36: rdata = g20; 8'h37: rdata = g21; 8'h38: rdata = g22;
        8'h40: rdata = alpha; 8'h41: rdata = k_dt; 8'h42: rdata = d_max;
        default: rdata = 8'h00;
      endcase
    end
  end
endmodule
