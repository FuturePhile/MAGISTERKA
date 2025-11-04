// tb_pkg.sv
package tb_pkg;
  timeunit 1ns/1ps;

  // Clock & reset generator
  typedef struct packed { logic clk; logic rst_n; } clk_rst_t;

  task automatic gen_clk(input int half_ns, inout logic clk);
    forever begin #half_ns clk = ~clk; end
  endtask

  task automatic do_reset(output logic rst_n, input int cycles, input logic clk);
    rst_n = 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

  // MMIO single-cycle bus (cs, rd, wr, addr, wdata, rdata)
  task automatic mmio_write(
      output logic cs, output logic rd, output logic wr,
      output byte addr, output byte wdata, input logic clk,
      input byte a, input byte d
  );
    @(posedge clk);
    addr <= a; wdata <= d; cs <= 1; rd <= 0; wr <= 1;
    @(posedge clk);
    cs <= 0; wr <= 0;
  endtask

  function automatic byte mmio_read(
      output logic cs, output logic rd, output logic wr,
      output byte addr, input byte rdata, input logic clk,
      input byte a
  );
    @(posedge clk);
    addr <= a; cs <= 1; rd <= 1; wr <= 0;
    @(posedge clk);
    mmio_read = rdata;
    cs <= 0; rd <= 0;
  endfunction

  // Pulse CTRL bits: [3]=INIT, [2]=DT_MODE, [1]=REG_MODE, [0]=START (W1P)
  task automatic pulse_ctrl(
      output logic cs, output logic rd, output logic wr,
      output byte addr, output byte wdata, input logic clk,
      input bit start, input bit reg_mode, input bit dt_mode, input bit init
  );
    byte d = {init, dt_mode, reg_mode, start};
    mmio_write(cs,rd,wr,addr,wdata,clk, 8'h01, d);
  endtask

  // One evaluation: write T/dT, pulse START, wait STATUS.valid, measure latency
  task automatic eval_once(
      output logic cs, output logic rd, output logic wr,
      output byte addr, output byte wdata, input byte rdata, input logic clk,
      input  byte T, input byte dT, input bit reg_mode, input bit dt_mode,
      output byte G_out, output int latency_cycles
  );
    // Set modes (latch bits, no pulses)
    pulse_ctrl(cs,rd,wr,addr,wdata,clk, 0, reg_mode, dt_mode, 0);
    // Write inputs
    mmio_write(cs,rd,wr,addr,wdata,clk, 8'h02, T);
    if (!dt_mode) mmio_write(cs,rd,wr,addr,wdata,clk, 8'h03, dT);

    // START
    pulse_ctrl(cs,rd,wr,addr,wdata,clk, 1, reg_mode, dt_mode, 0);

    // Poll STATUS.valid and count cycles
    latency_cycles = 0;
    bit seen = 0;
    repeat (20) begin
      byte st = mmio_read(cs,rd,wr,addr,rdata,clk, 8'h00);
      latency_cycles++;
      if (st[0]) begin
        seen = 1;
        break;
      end
    end
    // Read result
    G_out = mmio_read(cs,rd,wr,addr,rdata,clk, 8'h04);

    // Assertions (REQ-230 latency ≤10, and we know your FSM is 2)
    assert(seen) else $fatal(1, "No VALID within 20 cycles");
    assert(latency_cycles <= 10) else $fatal(1, "Latency > 10 cycles");
    // Optional: check it’s exactly 2 for your FSM
    assert(latency_cycles == 2) else $error("Latency=%0d (expected 2)", latency_cycles);
  endtask

endpackage
