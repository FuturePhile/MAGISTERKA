// tb_top_mmio.sv
`timescale 1ns/1ps
import tb_pkg::*;

module tb_top_mmio;
  // DUT I/O
  logic clk = 0, rst_n;
  logic cs=0, rd=0, wr=0;
  byte  addr=8'h00, wdata=8'h00, rdata;

  // DUT
  top dut (
    .clk(clk), .rst_n(rst_n),
    .cs(cs), .rd(rd), .wr(wr),
    .addr(addr), .wdata(wdata), .rdata(rdata)
  );

  // Clock 50 MHz (20 ns period)
  initial gen_clk(10, clk);
  initial begin
    do_reset(rst_n, 4, clk);

    // === PoR checks (REQ-120/130) ===
    // No IRQ pin in top => passes by construction
    // Read STATUS and G right after reset
    byte st0 = mmio_read(cs,rd,wr,addr,rdata,clk, 8'h00);
    byte g0  = mmio_read(cs,rd,wr,addr,rdata,clk, 8'h04);
    assert(st0[0] == 1'b0) else $fatal(1, "STATUS.valid not 0 after reset");
    assert(g0  == 8'd0)    else $fatal(1, "G not 0 after reset");

    // === Open CSV (flat path to avoid Windows permission issues) ===
    integer fd;
    fd = $fopen("hw_eval.csv", "w");
    if (fd == 0) $fatal(1, "Cannot open hw_eval.csv");
    $fwrite(fd, "T,dT,REG_MODE,DT_MODE,G,lat\n");

    // Helper
    automatic task run_vec(input byte T, input byte dT, input bit rm, input bit dm);
      byte G; int lat;
      eval_once(cs,rd,wr,addr,wdata,rdata,clk, T,dT,rm,dm, G, lat);
      $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d\n", $signed(T), $signed(dT), rm, dm, G, lat);
    endtask

    // === Canonical vectors (REQ-010/030/050) ===
    // V1: T=0,dT=0 => G=50 (both 4/9 rules)
    run_vec(8'sd0, 8'sd0, 1'b0, 1'b0);
    run_vec(8'sd0, 8'sd0, 1'b1, 1'b0);

    // V2: T=+100 (pos plateau), dT=-100 (neg plateau) => G≈80
    run_vec(8'sd100, -8'sd100, 1'b0, 1'b0);
    run_vec(8'sd100, -8'sd100, 1'b1, 1'b0);

    // V3: T=-100, dT=+100 => G≈30
    run_vec(-8'sd100, 8'sd100, 1'b0, 1'b0);
    run_vec(-8'sd100, 8'sd100, 1'b1, 1'b0);

    // V4: Σw=0 guard (far outside at exact feet) => G=0
    run_vec(-8'sd128, 8'sd127, 1'b1, 1'b0); // X/Z-safe: clamp via signed bytes

    // === REG_MODE A/B sweep on same grid (REQ-030 stable switching) ===
    foreach (int Ti [int i]) begin end // dummy to satisfy some tools
    for (int T=-120; T<=120; T+=40) begin
      for (int dT=-120; dT<=120; dT+=40) begin
        run_vec(T, dT, 1'b0, 1'b0);
        run_vec(T, dT, 1'b1, 1'b0);
      end
    end

    // === DT_MODE=1 basic sanity (REQ-060/062)
    // INIT pulse then steady T => no spike, G near 50
    pulse_ctrl(cs,rd,wr,addr,wdata,clk, 0, /*rm*/1'b1, /*dm*/1'b1, /*init*/1'b1);
    // Evaluate with constant T=0 several times
    repeat (5) run_vec(8'sd0, 8'sd0, 1'b1, 1'b1);

    $fclose(fd);
    $display("Saved hw_eval.csv");
    $finish;
  end
endmodule
