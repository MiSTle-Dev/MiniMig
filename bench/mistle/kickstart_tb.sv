`timescale 1ns / 1ps
module kickstart_tb;
  reg clk = 0, host_clk = 0;
  always #7 clk = ~clk;
  always #2 host_clk = ~host_clk;
  reg reset = 1, select_strobe = 0;
  reg [ 2:0] selected = 0;
  reg [63:0] image_size = 0;
  wire accepted, consume, ready, loading;
  reg [19:0] source_index = 0;
  wire available = source_index < image_size && loading;
  function [7:0] pattern(input integer index);
    pattern = index[7:0] ^ index[15:8] ^ index[18:16];
  endfunction
  wire [7:0] data = pattern(source_index);
  wire [25:2] host_addr;
  wire [31:0] host_data;
  wire host_req;
  reg host_ack = 0;
  kickstart_loader #(.IDLE_TIMEOUT(500)) dut (.*);
  integer writes = 0, delay_count = 0;
  integer bus_state = 0;
  reg check_writes = 0;
  integer byte_index;
  reg [25:0] expected_address;
  reg [31:0] expected_data;
  always @(posedge clk) if (consume) source_index <= source_index + 1'b1;
  always @(posedge host_clk) begin
    host_ack <= 0;
    if (reset) begin
      bus_state   <= 0;
      delay_count <= 0;
    end else
      case (bus_state)
        0:
        if (host_req) begin
          delay_count <= 3 + (writes % 7);
          bus_state   <= 1;
        end
        1:
        if (delay_count == 0) begin
          host_ack  <= 1;
          bus_state <= 2;
        end else delay_count <= delay_count - 1;
        2: if (!host_req) bus_state <= 0;
      endcase
    if (host_req && host_ack && check_writes) begin
      byte_index = image_size == 262144 ? (writes / 2) * 4 : writes * 4;
      expected_address = 26'h0780000 + byte_index + ((image_size == 262144 && writes % 2) ? 262144 : 0);
      expected_data = {pattern(byte_index), pattern(byte_index + 1), pattern(byte_index + 2), pattern(byte_index + 3)};
      if ({host_addr, 2'b00} !== expected_address || host_data !== expected_data)
        $fatal(
            1,
            "ROM write %0d got %h/%h expected %h/%h",
            writes,
            {
              host_addr, 2'b00
            },
            host_data,
            expected_address,
            expected_data
        );
      writes = writes + 1;
    end
  end
  task upload(input integer size);
    @(negedge clk);
    source_index = 0;
    image_size = size;
    select_strobe = 1;
    writes = 0;
    check_writes = 1;
    #1;
    if (!accepted) $fatal(1, "valid ROM rejected");
    @(negedge clk);
    select_strobe = 0;
    wait (ready);
    repeat (5) @(posedge clk);
    if (writes != 131072 || source_index != size || host_req)
      $fatal(1, "early/late completion %0d %0d", writes, source_index);
    check_writes = 0;
  endtask
  initial begin
    repeat (10) @(posedge clk);
    @(negedge clk);
    reset = 0;
    upload(262144);
    upload(524288);
    @(negedge clk);
    image_size = 123;
    select_strobe = 1;
    #1;
    if (accepted) $fatal(1, "invalid image accepted");
    @(negedge clk);
    select_strobe = 0;
    repeat (5) @(posedge clk);
    if (ready || loading) $fatal(1, "invalid selection retained a ready ROM");
    // A valid selection with no data times out without releasing the Amiga.
    @(negedge clk);
    source_index = 524288;
    image_size = 262144;
    select_strobe = 1;
    @(negedge clk);
    select_strobe = 0;
    repeat (510) @(posedge clk);
    if (ready || loading) $fatal(1, "interrupted upload did not time out");
    upload(262144);
    $display(
        "PASS Kickstart: full 256/512 KiB uploads, physical address/data, 256 KiB mirroring, delayed bus ACK, rejection, timeout/retry");
    $finish;
  end
  initial begin
    #200000000;
    $fatal(1, "ROM upload timeout");
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
