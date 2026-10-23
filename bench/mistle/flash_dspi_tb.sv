`timescale 1ns / 1ps
module flash_dspi_tb;
  reg clk = 0, flash_clk = 0;
  realtime host_half = 4.375;
  always #(host_half) clk = ~clk;
  initial begin
    #3.125;
    forever #17.5 flash_clk = ~flash_clk;
  end
  reg reset = 1, abort = 0;
  wire flash_ready, flash_busy, flash_cs, host_req, ready, quiescent;
  wire [22:0] flash_address;
  wire [15:0] flash_data;
  wire [25:2] host_addr;
  wire [31:0] host_data;
  reg host_ack = 0;
  tri1 mspi_cs, mspi_di, mspi_do, mspi_wp, mspi_hold;

  flash_dspi_reader transport (
    .clk(clk), .flash_clk(flash_clk), .reset(reset),
    .address(flash_address), .cs(flash_cs), .dout(flash_data),
    .busy(flash_busy), .ready(flash_ready),
    .mspi_cs(mspi_cs), .mspi_di(mspi_di), .mspi_do(mspi_do),
    .mspi_wp(mspi_wp), .mspi_hold(mspi_hold)
  );
  flash_boot #(.LONGWORDS(8)) boot (.*);

  // Pin-level BBh model: command/address/mode latch on SCK rising edges;
  // dual data becomes valid 6 ns after falling edges. SCK is flash_clk itself.
  localparam COMMAND = 0, ADDRESS = 1, MODE = 2, DATA = 3, ESCAPE = 4;
  integer chip_state = COMMAND, bits = 0, cycles = 0, samples = 0;
  integer full_reads = 0, continuous_reads = 0, escapes = 0;
  reg continuous_mode = 0, transaction_active = 0;
  reg [7:0] command, mode_bits;
  reg [23:0] byte_address;
  reg [23:0] expected_byte_address = 24'h400000;
  reg [15:0] shift_data;
  reg [1:0] chip_data;
  reg chip_drives = 0;
  assign mspi_di = chip_drives ? chip_data[0] : 1'bz;
  assign mspi_do = chip_drives ? chip_data[1] : 1'bz;

  always @(posedge reset) expected_byte_address = 24'h400000;

  function automatic [15:0] word_at(input [22:0] address);
    word_at = {address[7:0] ^ 8'h3c, address[15:8] ^ {1'b0, address[22:16]} ^ 8'ha7};
  endfunction

  always @(negedge mspi_cs) begin
    transaction_active = 1;
    chip_state = continuous_mode ? ADDRESS : COMMAND;
    bits = 0;
    cycles = 0;
    samples = 0;
    command = 0;
    mode_bits = 0;
    byte_address = 0;
  end

  always @(posedge flash_clk) begin
    if (transaction_active && !mspi_cs) begin
      cycles = cycles + 1;
      case (chip_state)
        COMMAND: begin
          command = {command[6:0], mspi_di};
          bits = bits + 1;
          if (bits == 8) begin
            bits = 0;
            if (command == 8'hff) chip_state = ESCAPE;
            else if (command == 8'hbb) chip_state = ADDRESS;
            else $fatal(1, "invalid DSPI command %h", command);
          end
        end
        ADDRESS: begin
          byte_address = {byte_address[21:0], mspi_do, mspi_di};
          bits = bits + 2;
          if (bits == 24) begin
            bits = 0;
            chip_state = MODE;
          end
        end
        MODE: begin
          mode_bits = {mode_bits[5:0], mspi_do, mspi_di};
          bits = bits + 2;
          if (bits == 8) begin
            if (mode_bits[5:4] == 2'b11 && byte_address == 24'hffffff) chip_state = ESCAPE;
            else begin
              if (mode_bits[5:4] !== 2'b10 || byte_address[0])
                $fatal(1, "invalid DSPI mode/address %h/%h", mode_bits, byte_address);
              if (byte_address !== expected_byte_address)
                $fatal(1, "DSPI address %h, expected %h", byte_address, expected_byte_address);
              expected_byte_address = expected_byte_address + 2;
              shift_data = word_at(byte_address[23:1]);
              chip_state = DATA;
            end
          end
        end
        DATA: begin
          if (^{mspi_do, mspi_di} === 1'bx) $fatal(1, "DSPI bus contention or undriven data");
          samples = samples + 1;
        end
        ESCAPE: if (mspi_di !== 1'b1) $fatal(1, "invalid continuous-mode exit sequence");
      endcase
    end
  end

  always @(negedge flash_clk) begin
    if (transaction_active && !mspi_cs && chip_state == DATA) begin
      chip_drives <= 1;
      chip_data <= #6 shift_data[15:14];
      shift_data = {shift_data[13:0], 2'b0};
    end
  end

  always @(posedge mspi_cs) begin
    chip_drives <= 0;
    if (transaction_active && !reset) begin
      if (chip_state == ESCAPE) begin
        if (cycles != 16) $fatal(1, "mode exit uses %0d clocks instead of 16", cycles);
        continuous_mode = 0;
        escapes = escapes + 1;
      end else begin
        if (chip_state != DATA || samples != 8)
          $fatal(1, "incomplete DSPI data: state %0d, samples %0d", chip_state, samples);
        if (continuous_mode) begin
          if (cycles != 24) $fatal(1, "continuous read uses %0d clocks", cycles);
          continuous_reads = continuous_reads + 1;
        end else begin
          if (cycles != 32) $fatal(1, "initial read uses %0d clocks", cycles);
          full_reads = full_reads + 1;
        end
        continuous_mode = 1;
      end
    end
    transaction_active = 0;
  end

  integer writes = 0, host_delay = 0;
  reg host_seen = 0, check_copy = 1;
  reg [25:2] pending_addr;
  reg [31:0] pending_data;
  always @(negedge clk) begin
    host_ack = 0;
    if (reset) begin
      writes = 0;
      host_delay = 0;
      host_seen = 0;
    end else if (host_req && !host_seen) begin
      host_seen = 1;
      host_delay = 9;
      pending_addr = host_addr;
      pending_data = host_data;
    end else if (host_req && host_delay != 0) begin
      if (host_addr !== pending_addr || host_data !== pending_data)
        $fatal(1, "host request changed before ACK");
      host_delay = host_delay - 1;
      if (host_delay == 0) begin
        if (check_copy && (host_addr !== 24'h1e0000 + writes ||
            host_data !== {word_at(23'h200000 + writes * 2), word_at(23'h200001 + writes * 2)}))
          $fatal(1, "flash payload/address mismatch at %0d: %h %h", writes, host_addr, host_data);
        writes = writes + 1;
        host_ack = 1;
      end
    end else if (!host_req) host_seen = 0;
  end

  task restart;
    begin
      @(negedge clk);
      reset = 1;
      abort = 0;
      repeat (12) @(posedge flash_clk);
      @(negedge clk);
      reset = 0;
    end
  endtask

  initial begin
    restart;
    wait (ready);
    #1;
    if (writes != 8 || !quiescent || full_reads != 1 || continuous_reads != 15 || escapes != 1)
      $fatal(1, "initial ROM copy/continuous read counts failed");
    // Reset while flash remains in continuous mode; init must exit that mode.
    host_half = 6.125;
    restart;
    wait (ready);
    #1;
    if (writes != 8 || full_reads != 2 || continuous_reads != 30 || escapes != 2)
      $fatal(1, "restart in continuous mode failed");
    restart;
    wait (host_req);
    @(negedge clk);
    abort = 1;
    if (quiescent) $fatal(1, "Companion acquired an outstanding host write");
    wait (quiescent);
    #1;
    if (ready || host_req || writes != 1) $fatal(1, "abort did not drain the host write");
    repeat (200) @(posedge flash_clk);
    if (host_req || flash_cs || !mspi_cs) $fatal(1, "reader restarted after abort");
    restart;
    wait (chip_state == DATA && samples == 3);
    @(negedge clk);
    abort = 1;
    wait (quiescent);
    repeat (200) @(posedge flash_clk);
    if (ready || host_req || flash_cs || !mspi_cs || writes != 0)
      $fatal(1, "abort in DSPI transfer issued a host write or restarted");
    // Reset in a pin-level transaction, then complete another verified ROM copy.
    restart;
    wait (chip_state == DATA && samples == 3);
    restart;
    wait (ready);
    #1;
    if (writes != 8 || !quiescent) $fatal(1, "reset in DSPI transfer failed");
    $display("PASS DSPI: unshifted 28 MHz, BBh/continuous reads, pin data timing, CDC, reset and abort/drain");
    $finish;
  end
  initial begin
    #500000;
    $fatal(1, "DSPI test timeout");
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
