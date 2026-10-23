`timescale 1ns / 1ps
module sdram_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg [2:0] command = 3'b111;
  reg [1:0] bank = 0, mask = 0;
  reg [3:0] address = 0;
  reg drive = 0;
  reg [15:0] write_data = 0;
  wire [15:0] dq;
  assign dq = drive ? write_data : 16'hzzzz;
  sdr_chip_model #(
      .ROW_WIDTH(4),
      .COL_WIDTH(4),
      .CASDELAY (2)
  ) dut (
      .clk(clk),
      .dq(dq),
      .addr(address),
      .dqm(mask),
      .ba(bank),
      .cs_n(1'b0),
      .ras_n(command[2]),
      .cas_n(command[1]),
      .we_n(command[0])
  );
  integer cycle = 0, checks = 0;
  reg [15:0] expected[0:255];
  reg expected_valid[0:255];
  function [15:0] value(input integer b, input integer column);
    value = 16'ha000 | (b << 8) | column;
  endfunction
  always @(posedge clk) begin
    cycle = cycle + 1;
    #1;
    if (expected_valid[cycle]) begin
      if (dq !== expected[cycle])
        $fatal(1, "CAS/bank/burst at cycle %0d got %h expected %h", cycle, dq, expected[cycle]);
      checks = checks + 1;
    end
  end
  task cmd(input [2:0] op, input [1:0] b, input [3:0] a);
    @(negedge clk);
    command = op;
    bank = b;
    address = a;
    drive = op == 3'b100;
    @(posedge clk);
    #2;
  endtask
  task read_cmd(input integer b, input integer col, input integer words);
    @(negedge clk);
    command = 3'b101;
    bank = b;
    address = col;
    drive = 0;
    for (integer i = 0; i < words; i = i + 1) begin
      expected_valid[cycle+3+i] = 1;
      expected[cycle+3+i] = value(b, (col & ~7) | ((col + i) & 7));
    end
    @(posedge clk);
    #2;
  endtask
  initial begin
    for (integer i = 0; i < 256; i = i + 1) expected_valid[i] = 0;
    // Different banks deliberately hold different active rows and payloads.
    for (integer b = 0; b < 4; b = b + 1) begin
      cmd(3'b011, b, b + 1);
      for (integer col = 0; col < 8; col = col + 1) begin
        write_data = value(b, col);
        cmd(3'b100, b, col);
      end
    end
    cmd(3'b000, 0, 0);  // burst length 1
    read_cmd(0, 0, 1);
    read_cmd(1, 1, 1);  // back-to-back bank reads preserve both pending results
    for (integer i = 0; i < 4; i = i + 1) cmd(3'b111, 0, 0);
    cmd(3'b000, 0, 3);  // burst length 8
    read_cmd(0, 0, 8);
    cmd(3'b011, 3, 12);  // changing another bank's row must not redirect the active burst
    for (integer i = 0; i < 10; i = i + 1) cmd(3'b111, 0, 0);
    read_cmd(0, 0, 1);  // next bank READ interrupts the burst, not the older CAS pipeline
    read_cmd(1, 0, 8);
    for (integer i = 0; i < 11; i = i + 1) cmd(3'b111, 0, 0);
    // Byte masks retain the masked byte.
    mask = 0;
    write_data = 16'habcd;
    cmd(3'b100, 2, 3);
    mask = 1;
    write_data = 16'h1234;
    cmd(3'b100, 2, 3);
    mask = 0;
    cmd(3'b000, 0, 0);
    @(negedge clk);
    command = 3'b101;
    bank = 2;
    address = 3;
    drive = 0;
    expected_valid[cycle+3] = 1;
    expected[cycle+3] = 16'h12cd;
    @(posedge clk);
    #2;
    for (integer i = 0; i < 4; i = i + 1) cmd(3'b111, 0, 0);
    if (checks != 20) $fatal(1, "missing SDRAM checks %0d", checks);
    $display(
        "PASS SDRAM model: CASDELAY=2, bank-interleaved reads, independent active rows, burst continuation/interruption and byte masks");
    $finish;
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
