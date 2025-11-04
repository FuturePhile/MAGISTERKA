// tb_aggregator_unit.sv
`timescale 1ns/1ps

module tb_aggregator_unit;
  // Simple case: only w11 is 1, all g=50 => S_w=1.0, S_wg=0.5 -> G≈50%
  logic reg_mode=1;
  logic [15:0] w00=0,w01=0,w02=0,w10=0,w11=16'h7FFF,w12=0,w20=0,w21=0,w22=0;
  logic [7:0] g00=50,g01=50,g02=50,g10=50,g11=50,g12=50,g20=50,g21=50,g22=50;
  logic [15:0] S_w,S_wg;
  aggregator u(.reg_mode(reg_mode),.*);

  initial begin
    #1 assert(S_w  == 16'h7FFF);
       assert(S_wg >= 16'd16383 && S_wg <= 16'd16384); // 0.5 in Q1.15
    $finish;
  end
endmodule
