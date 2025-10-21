`timescale 1ns/1ps
module tb_mmio_map;
  logic clk=0, rst_n=0; always #5 clk=~clk;
  logic cs,rd,wr; logic [7:0] addr,wdata,rdata;
  logic status_busy,status_valid;

  top dut(.clk(clk), .rst_n(rst_n), .cs(cs), .rd(rd), .wr(wr),
          .addr(addr), .wdata(wdata), .rdata(rdata),
          .status_busy(status_busy), .status_valid(status_valid));

  task automatic wr8(input [7:0] a, input [7:0] d);
    @(posedge clk); cs=1; wr=1; rd=0; addr=a; wdata=d;
    @(posedge clk); cs=0; wr=0; rd=0; addr=0; wdata=0;
  endtask
  task automatic rd8(input [7:0] a, output [7:0] d);
    @(posedge clk); cs=1; rd=1; wr=0; addr=a;
    @(posedge clk); d=rdata;
    @(posedge clk); cs=0; rd=0; wr=0; addr=0;
  endtask

  byte unsigned rdv;

  initial begin
    // reset
    cs=0; rd=0; wr=0; addr=0; wdata=0;
    repeat(2) @(posedge clk); rst_n=1; @(posedge clk);

    // REQ-120: write->read verify selected addresses (spot-check all regions)
    wr8(8'h10, 8'hA1); rd8(8'h10, rdv); assert(rdv==8'hA1); // T_neg_a
    wr8(8'h1F, 8'h3C); rd8(8'h1F, rdv); assert(rdv==8'h3C); // dT_neg_d
    wr8(8'h24, 8'd7 ); rd8(8'h24, rdv); assert(rdv==8'd7 ); // dT_pos_a
    wr8(8'h30, 8'd55); rd8(8'h30, rdv); assert(rdv==8'd55); // g00
    wr8(8'h38, 8'd90); rd8(8'h38, rdv); assert(rdv==8'd90); // g22
    wr8(8'h40, 8'd12); rd8(8'h40, rdv); assert(rdv==8'd12); // ALPHA
    wr8(8'h41, 8'd3 ); rd8(8'h41, rdv); assert(rdv==8'd3 ); // K_DT
    wr8(8'h42, 8'd64); rd8(8'h42, rdv); assert(rdv==8'd64); // D_MAX

    // dT write ignored when DT_MODE=1
    wr8(8'h01, 8'b0000_0110); // REG_MODE=1, DT_MODE=1
    wr8(8'h03, 8'hEE); rd8(8'h03, rdv); assert(rdv!=8'hEE);

    $display("tb_mmio_map: PASS");
    $finish;
  end
endmodule
