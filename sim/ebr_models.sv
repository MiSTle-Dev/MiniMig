// Behavioral equivalents of the IcePi EBR wrappers for Verilator.
// Port widths, byte lanes, synchronous read latency and write-through match the production wrappers.
module dpram_be_1024x32 (
    input [31:0] data_a,
    data_b,
    input [3:0] byteena_a,
    byteena_b,
    input [9:0] address_a,
    address_b,
    input clock,
    wren_a,
    wren_b,
    output reg [31:0] q_a,
    q_b
);
  reg [31:0] mem[0:1023];
  initial for (integer i = 0; i < 1024; i = i + 1) mem[i] = 0;
  always @(posedge clock) begin
    q_a <= mem[address_a];
    q_b <= mem[address_b];
    for (integer i = 0; i < 4; i = i + 1) begin
      if (wren_a && byteena_a[i]) begin
        mem[address_a][i*8+:8] <= data_a[i*8+:8];
        q_a[i*8+:8] <= data_a[i*8+:8];
      end
      if (wren_b && byteena_b[i]) begin
        mem[address_b][i*8+:8] <= data_b[i*8+:8];
        q_b[i*8+:8] <= data_b[i*8+:8];
      end
    end
  end
endmodule
module spram_be_512x32 (
    input clk,
    input [3:0] wren,
    input [8:0] addr,
    input [31:0] w,
    output reg [31:0] q
);
  reg [31:0] mem[0:511];
  initial for (integer i = 0; i < 512; i = i + 1) mem[i] = 0;
  always @(posedge clk) begin
    q <= mem[addr];
    for (integer i = 0; i < 4; i = i + 1) if (wren[i]) mem[addr][i*8+:8] <= w[i*8+:8];
  end
endmodule
module denise_colortable_ram_mf (
    input [7:0] wraddress,
    rdaddress,
    input [31:0] data,
    input enable,
    input [3:0] byteena_a,
    input wren,
    clock,
    output reg [31:0] q
);
  reg [31:0] mem[0:255];
  initial for (integer i = 0; i < 256; i = i + 1) mem[i] = 0;
  always @(posedge clock)
    if (enable) begin
      q <= mem[rdaddress];
      for (integer i = 0; i < 4; i = i + 1) if (wren && byteena_a[i]) mem[wraddress][i*8+:8] <= data[i*8+:8];
    end
endmodule
module sector_dpram (
    input [7:0] dina,
    dinb,
    input [8:0] ada,
    adb,
    input clka,
    clkb,
    cea,
    ceb,
    ocea,
    oceb,
    wrea,
    wreb,
    reseta,
    resetb,
    output reg [7:0] douta,
    doutb
);
  reg [7:0] mem[0:511];
  initial for (integer i = 0; i < 512; i = i + 1) mem[i] = 0;
  always @(posedge clka)
    if (cea) begin
      if (wrea) mem[ada] <= dina;
      if (reseta) douta <= 0;
      else if (ocea) douta <= mem[ada];
    end
  always @(posedge clkb)
    if (ceb) begin
      if (wreb) mem[adb] <= dinb;
      if (resetb) doutb <= 0;
      else if (oceb) doutb <= mem[adb];
    end
endmodule
module paula_floppy_dma_buf (
    input [15:0] dina,
    dinb,
    input [1:0] bsa,
    bsb,
    input [7:0] addra,
    addrb,
    input clk,
    wrena,
    wrenb,
    output reg [15:0] douta,
    doutb
);
  reg [15:0] mem[0:255];
  initial for (integer i = 0; i < 256; i = i + 1) mem[i] = 0;
  always @(posedge clk) begin
    douta <= mem[addra];
    doutb <= mem[addrb];
    if (wrena) for (integer i = 0; i < 2; i = i + 1) if (bsa[i]) mem[addra][i*8+:8] <= dina[i*8+:8];
    if (wrenb) for (integer i = 0; i < 2; i = i + 1) if (bsb[i]) mem[addrb][i*8+:8] <= dinb[i*8+:8];
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
