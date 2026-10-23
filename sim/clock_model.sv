module amiga_clk_lattice_pll (
    input  areset,
    input  inclk0,
    output c0,
    output c1,
    output c2,
    output c3,
    output c4,
    output locked
);
  reg [5:0] count = 0;
  always @(posedge inclk0)
    if (areset) count <= 0;
    else if (!(&count[5:2])) count <= count + 1'b1;
    else count[1:0] <= count[1:0] + 1'b1;
  assign c0 = ~inclk0;
  assign c1 = inclk0;
  assign c2 = count[1];
  assign c3 = count[0];
  assign c4 = inclk0;
  assign locked = &count[5:2];
endmodule
module gsr_pur_assign (
    output GSR_sig,
    output PUR_sig
);
  assign GSR_sig = 1'b1;
  assign PUR_sig = 1'b1;
endmodule
// vim: ts=2 sw=2 tw=120 et
