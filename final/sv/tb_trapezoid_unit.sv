// tb_trapezoid_unit.sv
`timescale 1ns/1ps

module tb_trapezoid_unit;
  logic signed [7:0] x,a,b,c,d;
  logic [15:0] mu;
  trapezoid u(.x(x),.a(a),.b(b),.c(c),.d(d),.mu(mu));

  initial begin
    a=-8'sd100; b=-8'sd50; c=8'sd50; d=8'sd100;

    // Outside
    x = -8'sd120; #1 assert(mu==0);
    x =  8'sd120; #1 assert(mu==0);

    // Plateau
    x = -8'sd40;  #1 assert(mu==16'h7FFF);
    x =  8'sd40;  #1 assert(mu==16'h7FFF);

    // Slopes monotonic
    int last=0;
    for (int xi=a+1; xi<b; xi++) begin
      x=xi; #1 assert(mu>=last); last=mu;
    end
    last=16'h7FFF;
    for (int xi=c+1; xi<d; xi++) begin
      x=xi; #1 assert(mu<=last); last=mu;
    end

    // Degenerate shoulders (b==a)
    a=-8'sd50; b=-8'sd50; c=8'sd50; d=8'sd100;
    x=-8'sd49; #1 assert(mu==16'h7FFF); // instant shoulder still legal (den=1)
    $finish;
  end
endmodule
