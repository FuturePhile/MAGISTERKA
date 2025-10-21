`timescale 1ns/1ps

module tb_top_mmio_smoke;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;

  // MMIO
  logic cs, rd, wr;
  logic [7:0] addr, wdata, rdata;
  logic status_busy, status_valid;

  top dut (
    .clk(clk), .rst_n(rst_n),
    .cs(cs), .rd(rd), .wr(wr), .addr(addr), .wdata(wdata), .rdata(rdata),
    .status_busy(status_busy), .status_valid(status_valid)
  );

  // ---------------- MMIO driver tasks ----------------
  task automatic mmio_write(input [7:0] a, input [7:0] d);
    @(posedge clk); cs=1; wr=1; rd=0; addr=a; wdata=d;
    @(posedge clk); cs=0; wr=0; rd=0; addr=0; wdata=0;
  endtask

  task automatic mmio_read(input [7:0] a, output [7:0] d);
    @(posedge clk); cs=1; rd=1; wr=0; addr=a;
    @(posedge clk); d = rdata;
    @(posedge clk); cs=0; rd=0; wr=0; addr=0;
  endtask

  // Compose and write CTRL: [0]=start (pulse), [1]=REG_MODE, [2]=DT_MODE, [3]=INIT (pulse)
  task automatic write_ctrl(input bit start, input bit reg_mode, input bit dt_mode, input bit init);
    bit [7:0] v;
    v = {4'b0, init, dt_mode, reg_mode, start};
    mmio_write(8'h01, v);
  endtask

  // ---------------- Test sequence ----------------
  initial begin
    byte unsigned st, ctrl_rd, gout, dt_rd;

    // Reset
    cs=0; rd=0; wr=0; addr=0; wdata=0;
    repeat(2) @(posedge clk);
    rst_n = 1; @(posedge clk);

    // REQ-120: set REG_MODE=1 (9 rules), DT_MODE=0 (external dT)
    write_ctrl(0, 1, 0, 0);

    // Check CTRL readback: pulse bits read as 0, mode bits preserved
    mmio_read(8'h01, ctrl_rd);
    assert(ctrl_rd[0] == 1'b0 && ctrl_rd[3] == 1'b0)
      else $fatal("REQ-120: CTRL pulse bits must read as 0");
    assert(ctrl_rd[2] == 1'b0 && ctrl_rd[1] == 1'b1)
      else $fatal("REQ-120: CTRL mode bits mismatch (dt_mode/reg_mode)");

    // Set simple MF for both T and dT: triangle around 0 (a=-64,b=0,c=0,d=+64)
    mmio_write(8'h10, -8'sd64); mmio_write(8'h11, 8'sd0);  mmio_write(8'h12, 8'sd0);  mmio_write(8'h13, 8'sd64);
    mmio_write(8'h1C, -8'sd64); mmio_write(8'h1D, 8'sd0);  mmio_write(8'h1E, 8'sd0);  mmio_write(8'h1F, 8'sd64);
    // zero/pos sets (quick default)
    mmio_write(8'h14, -8'sd32); mmio_write(8'h15, -8'sd1); mmio_write(8'h16,  8'sd1); mmio_write(8'h17, 8'sd32);
    mmio_write(8'h18,  8'sd0 ); mmio_write(8'h19, 8'sd32); mmio_write(8'h1A, 8'sd64); mmio_write(8'h1B, 8'sd80);
    // dT ZERO/POS
    mmio_write(8'h20, -8'sd32); mmio_write(8'h21, -8'sd1); mmio_write(8'h22,  8'sd1); mmio_write(8'h23, 8'sd32);
    mmio_write(8'h24,  8'sd0 ); mmio_write(8'h25, 8'sd32); mmio_write(8'h26, 8'sd64); mmio_write(8'h27, 8'sd80);

    // Singletons: set g22=100% (pos,pos), others 0
    mmio_write(8'h30, 8'd0); mmio_write(8'h31, 8'd0); mmio_write(8'h32, 8'd0);
    mmio_write(8'h33, 8'd0); mmio_write(8'h34, 8'd0); mmio_write(8'h35, 8'd0);
    mmio_write(8'h36, 8'd0); mmio_write(8'h37, 8'd0); mmio_write(8'h38, 8'd100);

    // Provide inputs: T=+32, dT=+32 (external dT path)
    mmio_write(8'h02, 8'd32);
    mmio_write(8'h03, 8'd32);

    // Read back dT register in DT_MODE=0 (should equal what we wrote)
    mmio_read(8'h03, dt_rd);
    assert(dt_rd == 8'd32) else $fatal("REQ-110/120: dT readback mismatch");

    // Kick START
    write_ctrl(1, 1, 0, 0);

    // REQ-130/230: check busy/valid one-cycle behavior
    @(posedge clk); // cycle after START
    mmio_read(8'h00, st);
    assert(st[0] == 1 && st[1] == 0) else $fatal("REQ-130: busy should be 1, valid 0");

    @(posedge clk); // DONE cycle
    mmio_read(8'h00, st);
    assert(st[0] == 0 && st[1] == 1) else $fatal("REQ-230: valid should be 1 for one cycle");

    @(posedge clk); // back to IDLE
    mmio_read(8'h00, st);
    assert(st[0] == 0 && st[1] == 0) else $fatal("REQ-230: status should return to idle");

    // Read result (REQ-110 / datapath plausibility)
    mmio_read(8'h04, gout);
    assert(gout >= 8'd40 && gout <= 8'd60)
      else $fatal("REQ-050: G_out out of band: %0d", gout);

    $display("tb_top_mmio_smoke: PASS (G_out=%0d)", gout);
    $finish;
  end
endmodule
