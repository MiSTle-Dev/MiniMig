`timescale 1ns / 1ps
module flash_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1, abort = 0, flash_ready = 0, flash_busy = 0, host_ack = 0;
  reg  [15:0] flash_data = 0;
  wire [22:0] flash_address;
  wire flash_cs, host_req, ready, quiescent;
  wire [25:2] host_addr;
  wire [31:0] host_data;
  flash_boot #(.LONGWORDS(4)) dut (.*);
  integer reader_delay = 0, host_delay = 0, writes = 0;
  reg [22:0] selected_word;
  reg request_seen = 0;
  reg check_copy = 1;
  always @(negedge clk) begin
    host_ack = 0;
    if (reset) begin
      reader_delay = 0;
      host_delay   = 0;
      request_seen = 0;
      flash_busy   = 0;
    end else begin
      if (flash_cs && !flash_busy) begin
        flash_busy = 1;
        reader_delay = 4;
        selected_word = flash_address;
      end else if (flash_busy) begin
        if (reader_delay == 0) begin
          flash_data = 16'ha500 ^ selected_word[15:0];
          flash_busy = 0;
        end else reader_delay = reader_delay - 1;
      end
      if (host_req && !request_seen) begin
        host_delay   = 5;
        request_seen = 1;
      end else if (host_req && host_delay != 0) begin
        host_delay = host_delay - 1;
        if (host_delay == 0) begin
          host_ack = 1;
          if(check_copy && (host_addr!==24'h1e0000+writes ||
              host_data!=={16'ha500^(16'(writes*2)),16'ha500^(16'(writes*2+1))}))
            $fatal(1, "flash copy address/data at %0d: %h %h", writes, host_addr, host_data);
          writes = writes + 1;
        end
      end
      if (!host_req) request_seen = 0;
    end
  end
  initial begin
    repeat (4) @(posedge clk);
    @(negedge clk);
    reset = 0;
    repeat (8) @(posedge clk);
    if (host_req || flash_cs) $fatal(1, "flash started before reader ready");
    @(posedge clk);
    flash_ready = 1;
    wait (ready);
    #1;
    if (!quiescent || writes != 4) $fatal(1, "flash completion mismatch");
    @(posedge clk);
    reset = 1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    reset = 0;
    check_copy = 0;
    wait (host_req);
    @(posedge clk);
    abort = 1;
    if (quiescent) $fatal(1, "flash released bus before an outstanding write drained");
    wait (quiescent);
    #1;
    if (ready || host_req) $fatal(1, "flash abort left ROM ready or bus active");
    repeat (30) @(posedge clk);
    if (host_req || flash_cs) $fatal(1, "flash restarted after Companion override");
    $display(
        "PASS flash boot: offset 0x400000, paired words, stable SDRAM address/data, completion and Companion abort/drain");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "flash timeout");
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
