`timescale 1ns / 1ps
module storage_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1, amiga_reset = 0;
  reg [ 7:0] mounted = 0;
  reg [63:0] image_size = 0;
  wire cmd_req, dat_req;
  wire [15:0] hd_in, hd_out, metadata;
  wire [2:0] hd_addr;
  wire hd_wr, hd_status, hd_write, hd_read;
  reg  [ 2:0] address = 7;
  reg  [15:0] guest_in = 0;
  wire [15:0] guest_out;
  reg rd = 0, hwr = 0, lwr = 0;
  wire drq, nrdy;
  wire [1:0] irq;
  ide backend (
      .clk(clk),
      .clk_en(1'b1),
      .reset(reset || amiga_reset),
      .drq(drq),
      .address_in(address),
      .sel_secondary(1'b0),
      .data_in(guest_in),
      .data_out(guest_out),
      .data_oe(),
      .rd(rd),
      .hwr(hwr),
      .lwr(lwr),
      .sel_ide(1'b1),
      .intreq(irq),
      .intreq_ack(2'b0),
      .nrdy(nrdy),
      .hdd0_ena(2'b11),
      .hdd1_ena(2'b0),
      .fifo_rd(),
      .fifo_wr(),
      .hdd_cmd_req(cmd_req),
      .hdd_dat_req(dat_req),
      .hdd_addr(hd_addr),
      .hdd_data_out(hd_out),
      .hdd_data_in(hd_in),
      .hdd_wr(hd_wr),
      .hdd_status_wr(hd_status),
      .hdd_data_wr(hd_write),
      .hdd_data_rd(hd_read),
      .hdd_step(),
      .command_metadata(metadata)
  );
  reg [3:0] fdc_rd = 0, fdc_wr = 0;
  reg [31:0] fdc_sector = 0;
  wire fdc_busy, fdc_done, fdc_strobe;
  wire [7:0] sd_rd, sd_wr, write_data;
  wire [31:0] sector;
  reg busy = 0, done = 0, sd_error = 0, strobe = 0;
  reg [8:0] byte_addr = 0;
  reg [7:0] read_data = 0;
  sdc_controller #(
      .TIMEOUT_CYCLES(20000)
  ) dut (
      .clk(clk),
      .reset(reset),
      .amiga_reset(amiga_reset),
      .image_mounted(mounted),
      .image_size(image_size),
      .hdd_cmd_req(cmd_req),
      .hdd_dat_req(dat_req),
      .hdd_data_in(hd_in),
      .hdd_metadata(metadata),
      .hdd_addr(hd_addr),
      .hdd_data_out(hd_out),
      .hdd_wr(hd_wr),
      .hdd_status_wr(hd_status),
      .hdd_data_wr(hd_write),
      .hdd_data_rd(hd_read),
      .fdc_rd(fdc_rd),
      .fdc_wr(fdc_wr),
      .fdc_sector(fdc_sector),
      .fdc_write_data(8'h5a),
      .fdc_busy(fdc_busy),
      .fdc_done(fdc_done),
      .fdc_strobe(fdc_strobe),
      .sd_rd(sd_rd),
      .sd_wr(sd_wr),
      .sd_sector(sector),
      .sd_busy(busy),
      .sd_done(done),
      .sd_error(sd_error),
      .sd_strobe(strobe),
      .sd_addr(byte_addr),
      .sd_read_data(read_data),
      .sd_write_data(write_data)
  );
  integer requests = 0, writes = 0, count = 0, phase = 0, selected = 0;
  integer fdc_bytes = 0, fdc_completions = 0, hdd_bytes = 0;
  reg [31:0] active_sector;
  reg active_write;
  reg [7:0] written[0:511];
  reg fail_next = 0, active_error = 0;
  reg stall_transport = 0;
  reg [15:0] rdb_heads[0:1];
  reg [15:0] rdb_sectors[0:1];
  reg [15:0] rdb_cylinders[0:1];
  function [7:0] disk_byte(input integer slot, input [31:0] lba, input integer index);
    begin
      disk_byte = (index ^ lba ^ (slot * 31));
      if (lba == 0) begin
        disk_byte = 0;
        case (index)
          0:  disk_byte = "R";
          1:  disk_byte = "D";
          2:  disk_byte = "S";
          3:  disk_byte = "K";
          66: disk_byte = rdb_cylinders[slot == 5][15:8];
          67: disk_byte = rdb_cylinders[slot == 5][7:0];
          70: disk_byte = rdb_sectors[slot == 5][15:8];
          71: disk_byte = rdb_sectors[slot == 5][7:0];
          74: disk_byte = rdb_heads[slot == 5][15:8];
          75: disk_byte = rdb_heads[slot == 5][7:0];
        endcase
      end
    end
  endfunction
  // Byte-accurate transport model with held addresses and a delayed completion.
  always @(negedge clk) begin
    strobe = 0;
    done = 0;
    sd_error = 0;
    if (reset) begin
      busy  = 0;
      phase = 0;
    end else if (!busy && (|sd_rd || |sd_wr)) begin
      if (((sd_rd | sd_wr) & ((sd_rd | sd_wr) - 1)) != 0) $fatal(1, "nonexclusive request");
      selected = 0;
      for (integer i = 0; i < 8; i = i + 1) if (sd_rd[i] || sd_wr[i]) selected = i;
      active_sector = sector;
      active_write = |sd_wr;
      active_error = fail_next;
      fail_next = 0;
      busy = 1;
      count = 0;
      phase = 0;
      byte_addr = 0;
      requests = requests + 1;
      if (active_write) writes = writes + 1;
    end else if (busy && !stall_transport) begin
      phase = phase + 1;
      if (phase == 4 && count < 512) begin
        byte_addr = count;
        read_data = disk_byte(selected, active_sector, count);
        strobe = !active_write;
      end
      if (phase == 8) begin
        phase = 0;
        if (count < 512) begin
          if (active_write) written[count] = write_data;
          count = count + 1;
          if (count < 512) byte_addr = count;
        end else begin
          done = 1;
          sd_error = active_error;
          busy = 0;
        end
      end
    end
  end
  always @(posedge clk) begin
    if (fdc_strobe) begin
      fdc_bytes = fdc_bytes + 1;
      if (selected >= 4) $fatal(1, "HDD data leaked to floppy");
    end
    if (fdc_done) fdc_completions = fdc_completions + 1;
    if (dut.owner == 1 && strobe) hdd_bytes = hdd_bytes + 1;
    if (hd_write && $isunknown(hd_out)) $fatal(1, "unknown data reached IDE FIFO");
    if (amiga_reset && (hd_write || hd_status || hd_wr || hd_read)) $fatal(1, "stale service during reset");
  end
  task tick(input integer cycles);
    repeat (cycles) @(posedge clk);
  endtask
  task reg_write(input [2:0] addr, input [7:0] value);
    @(negedge clk);
    address = addr;
    guest_in = {value, 8'b0};
    hwr = 1;
    lwr = 0;
    tick(2);
    @(negedge clk);
    hwr = 0;
    tick(3);
  endtask
  task issue(input [7:0] command, input integer drive, input [31:0] lba, input [7:0] sectors);
    reg_write(2, sectors);
    reg_write(3, lba[7:0]);
    reg_write(4, lba[15:8]);
    reg_write(5, lba[23:16]);
    reg_write(6, {3'b111, drive[0], lba[27:24]});
    reg_write(7, command);
  endtask
  task await_drq;
    integer timeout;
    timeout = 0;
    while (!drq && timeout < 20000) begin
      tick(1);
      timeout = timeout + 1;
    end
    if (!drq) $fatal(1, "DRQ timeout state=%0d cmd=%h meta=%h", dut.state, dut.command, metadata);
    tick(3);
  endtask
  task read_word(output [15:0] value);
    @(negedge clk);
    address = 0;
    rd = 0;
    tick(3);
    @(negedge clk);
    rd = 1;
    tick(1);
    #1;
    value = guest_out;
    @(negedge clk);
    rd = 0;
    tick(3);
  endtask
  task write_word(input [15:0] value);
    @(negedge clk);
    address = 0;
    guest_in = value;
    hwr = 1;
    lwr = 1;
    tick(2);
    @(negedge clk);
    hwr = 0;
    lwr = 0;
    tick(2);
  endtask
  task read_sector(input integer slot, input [31:0] lba);
    reg [15:0] value, expected;
    await_drq;
    for (integer i = 0; i < 256; i = i + 1) begin
      read_word(value);
      expected = {disk_byte(slot, lba, 2 * i), disk_byte(slot, lba, 2 * i + 1)};
      if (value !== expected)
        $fatal(1, "sector %0d word %0d got %h expected %h state %0d", lba, i, value, expected, dut.state);
    end
  endtask
  task idle;
    integer timeout;
    timeout = 0;
    while ((dut.state != 0 || metadata[9] || busy) && timeout < 30000) begin
      tick(1);
      timeout = timeout + 1;
    end
    if (timeout == 30000) $fatal(1, "idle timeout state=%0d meta=%h", dut.state, metadata);
    tick(4);
  endtask
  task mount_image(input integer drive, input [63:0] bytes);
    @(negedge clk);
    image_size = bytes;
    mounted = 8'h10 << drive;
    tick(1);
    @(negedge clk);
    mounted = 0;
  endtask
  task probe_done(input integer drive);
    wait (dut.examined[drive]);
    tick(4);
  endtask
  task check_identify(input integer drive, input [28:0] capacity,
                      input [15:0] cylinders, heads, sectors, multi);
    reg [15:0] actual, expected;
    issue(8'hec, drive, 0, 1);
    await_drq;
    for (integer i = 0; i < 256; i = i + 1) begin
      read_word(actual);
      expected = 16'bx;
      case (i)
        1, 54: expected = cylinders;
        3, 55: expected = heads;
        6, 56: expected = sectors;
        57, 60: expected = capacity[15:0];
        58, 61: expected = {3'b0, capacity[28:16]};
        59: expected = multi == 0 ? 0 : 16'h0100 | multi;
      endcase
      if (expected !== 16'bx && actual !== {expected[7:0], expected[15:8]})
        $fatal(1, "IDENTIFY drive %0d word %0d got %h expected %h", drive, i, actual, expected);
    end
    idle;
  endtask
  integer before_requests;
  task reject_image(input [63:0] bytes);
    before_requests = requests;
    mount_image(1, bytes);
    tick(20);
    issue(8'hec, 1, 0, 1);
    idle;
    if (dut.present[1] !== 0 || dut.mounted[1] !== 0 || requests != before_requests || !backend.error)
      $fatal(1, "invalid image accepted: %h", bytes);
  endtask
  initial begin
    rdb_cylinders[0] = 64;
    rdb_cylinders[1] = 64;
    rdb_heads[0] = 2;
    rdb_heads[1] = 4;
    rdb_sectors[0] = 11;
    rdb_sectors[1] = 17;
    tick(8);
    @(negedge clk);
    reset = 0;
    // The RAM is initially unknown: validity must prevent a command from consuming it.
    before_requests = requests;
    issue(8'hec, 0, 0, 1);
    idle;
    if (!backend.error || requests != before_requests) $fatal(1, "uninitialized media was exposed");
    @(negedge clk);
    image_size = 64'd411648 * 512;
    mounted = 8'h10;
    tick(1);
    @(negedge clk);
    mounted = 0;
    image_size = 64'd1000 * 512;
    mounted = 8'h20;
    tick(1);
    @(negedge clk);
    mounted = 0;
    wait (dut.examined == 3);
    tick(4);
    check_identify(0, 411648, 64, 2, 11, 0);
    check_identify(1, 1000, 64, 4, 17, 0);
    issue(8'h20, 0, 411647, 1);
    read_sector(4, 411647);
    idle;
    before_requests = requests;
    issue(8'h20, 0, 411648, 1);
    idle;
    if (requests != before_requests || !backend.error) $fatal(1, "out-of-range read accepted");
    issue(8'h20, 1, 999, 1);
    read_sector(5, 999);
    idle;
    // CHS increment on drive 1 must use its geometry (4 heads, 17 sectors).
    reg_write(2, 2);
    reg_write(3, 17);
    reg_write(4, 0);
    reg_write(5, 0);
    reg_write(6, 8'hb0);
    reg_write(7, 8'h20);
    read_sector(5, 16);
    read_sector(5, 17);
    idle;
    before_requests = requests;
    issue(8'hc4, 0, 20, 1);
    idle;
    if (requests != before_requests || !backend.error) $fatal(1, "multiple mode starts enabled");
    issue(8'hc6, 0, 0, 2);
    idle;
    issue(8'hc6, 0, 0, 3);
    idle;
    if (dut.multiple[0] != 2 || !backend.error) $fatal(1, "invalid multiple setting changed mode");
    issue(8'hc4, 0, 20, 3);
    read_sector(4, 20);
    read_sector(4, 21);
    read_sector(4, 22);
    idle;
    issue(8'h30, 1, 99, 1);
    await_drq;
    for (integer i = 0; i < 256; i = i + 1) write_word({i[7:0], ~i[7:0]});
    idle;
    for (integer i = 0; i < 256; i = i + 1)
    if (written[2*i] !== i[7:0] || written[2*i+1] !== ~i[7:0])
      $fatal(1, "write byte order at %0d %h %h", i, written[2*i], written[2*i+1]);
    issue(8'hc5, 0, 200, 3);
    await_drq;
    for (integer sec = 0; sec < 3; sec = sec + 1)
    for (integer i = 0; i < 256; i = i + 1) write_word({sec[7:0], i[7:0]});
    idle;
    for (integer i = 0; i < 256; i = i + 1)
    if (written[2*i] !== 8'd2 || written[2*i+1] !== i[7:0]) $fatal(1, "multiple write lost payload %0d", i);
    // Drive 1 mount replacement is recognized even while already mounted.
    @(negedge clk);
    image_size = 512 * 2000;
    mounted = 8'h20;
    tick(1);
    @(negedge clk);
    mounted = 0;
    wait (dut.examined == 3);
    tick(4);
    check_identify(1, 2000, 64, 4, 17, 0);
    // Concurrent floppy/HDD activity keeps payload/completion ownership separate.
    issue(8'h20, 0, 80, 1);
    @(negedge clk);
    fdc_sector = 7;
    fdc_rd = 1;
    wait (fdc_busy && dut.owner == 2);
    @(negedge clk);
    fdc_rd = 0;
    read_sector(4, 80);
    idle;
    if (fdc_bytes != 512 || fdc_completions != 1) $fatal(1, "floppy arbitration %0d %0d", fdc_bytes, fdc_completions);
    // Reset cancels Amiga service while allowing an accepted SD transaction to drain.
    issue(8'h20, 0, 90, 1);
    wait (busy);
    @(negedge clk);
    amiga_reset = 1;
    tick(10);
    @(negedge clk);
    amiga_reset = 0;
    idle;
    issue(8'h20, 0, 91, 1);
    read_sector(4, 91);
    idle;
    // A replacement CPU command cancels the old generation while its sector is in flight.
    before_requests = requests;
    issue(8'h20, 0, 92, 1);
    wait (busy);
    issue(8'h20, 0, 93, 1);
    // While BSY is asserted the stable IDE protects taskfile registers; only the new generation is accepted.
    read_sector(4, 92);
    idle;
    if (requests != before_requests + 2) $fatal(1, "replacement generation reused an old sector transaction");
    issue(8'h20, 0, 93, 1);
    read_sector(4, 93);
    idle;
    // Ejecting media while busy aborts the guest command and drains only the accepted transfer.
    issue(8'h20, 1, 90, 1);
    wait (busy);
    @(negedge clk);
    image_size = 0;
    mounted = 8'h20;
    tick(1);
    @(negedge clk);
    mounted = 0;
    idle;
    if (!backend.error) $fatal(1, "eject left guest busy or failed to abort");
    // A zero sector count means 256 sectors, including the last image sector.
    issue(8'h20, 0, 411392, 0);
    for (integer sec = 0; sec < 256; sec = sec + 1) read_sector(4, 411392 + sec);
    idle;
    // Failed native writes propagate an error instead of success.
    fail_next = 1;
    issue(8'h30, 0, 100, 1);
    await_drq;
    for (integer i = 0; i < 256; i = i + 1) write_word(16'h1234);
    idle;
    if (!backend.error) $fatal(1, "SD write failure not propagated");
    // Unvalidated high geometry bits must not alias into the narrowed RAM fields.
    rdb_heads[1] = 16'h0104;
    mount_image(1, 512 * 3000);
    probe_done(1);
    if (dut.present[1] !== 0) $fatal(1, "oversized RDB heads accepted");
    before_requests = requests;
    issue(8'hec, 1, 0, 1);
    idle;
    if (!backend.error || requests != before_requests) $fatal(1, "invalid geometry exposed stale payload");
    rdb_heads[1] = 4;
    rdb_sectors[1] = 16'h0111;
    mount_image(1, 512 * 3000);
    probe_done(1);
    if (dut.present[1] !== 0) $fatal(1, "oversized RDB sectors accepted");
    rdb_sectors[1] = 17;
    reject_image(0);
    reject_image(511);
    reject_image(513);
    reject_image(64'h2000000200);

    // The count for a maximum LBA28 image needs bit 28; its last sector is valid.
    rdb_cylinders[1] = 16'hffff;
    rdb_heads[1] = 16;
    rdb_sectors[1] = 255;
    mount_image(1, 64'h2000000000);
    probe_done(1);
    check_identify(1, 29'h10000000, 16'hffff, 16, 255, 0);
    issue(8'h20, 1, 32'h0fffffff, 1);
    read_sector(5, 32'h0fffffff);
    idle;
    before_requests = requests;
    issue(8'h20, 1, 32'h0fffffff, 2);
    idle;
    if (!backend.error || requests != before_requests) $fatal(1, "LBA28 end crossing accepted");

    // Maximum accepted CHS fields still use the complete validated geometry.
    reg_write(2, 1);
    reg_write(3, 255);
    reg_write(4, 8'hfe);
    reg_write(5, 8'hff);
    reg_write(6, 8'hbf);
    reg_write(7, 8'h20);
    read_sector(5, 65535 * 16 * 255 - 1);
    idle;
    rdb_cylinders[1] = 64;
    rdb_heads[1] = 4;
    rdb_sectors[1] = 17;

    // Remount during a physical probe: drain the old transfer, then probe the new image.
    mount_image(1, 512 * 3000);
    wait (busy);
    mount_image(1, 512 * 3500);
    probe_done(1);
    check_identify(1, 3500, 64, 4, 17, 0);

    // Remount on the exact probe-commit cycle must invalidate the old row.
    mount_image(1, 512 * 3000);
    wait (dut.state == dut.PROBE_FINISH);
    mount_image(1, 512 * 4000);
    #1;
    if (dut.present[1] !== 0 || dut.examined[1] !== 0) $fatal(1, "stale probe won over remount");
    probe_done(1);
    check_identify(1, 4000, 64, 4, 17, 0);

    // A mount on the other drive takes the single write port; retry this probe's commit.
    mount_image(0, 512 * 5000);
    wait (dut.state == dut.PROBE_FINISH);
    mount_image(1, 512 * 6000);
    #1;
    if (dut.state !== dut.PROBE_FINISH || dut.present[0] !== 0)
      $fatal(1, "probe did not defer to other-drive mount");
    probe_done(0);
    probe_done(1);
    check_identify(0, 5000, 64, 2, 11, 0);
    check_identify(1, 6000, 64, 4, 17, 0);

    // Warm reset retains media but disables multiple mode independently of RAM payload.
    issue(8'hc6, 1, 0, 8);
    idle;
    check_identify(1, 6000, 64, 4, 17, 8);
    @(negedge clk);
    amiga_reset = 1;
    tick(4);
    @(negedge clk);
    amiga_reset = 0;
    check_identify(1, 6000, 64, 4, 17, 0);
    // Reset on probe completion must leave it unexamined so it can be retried.
    mount_image(1, 512 * 7000);
    wait (dut.state == dut.PROBE_FINISH);
    @(negedge clk);
    amiga_reset = 1;
    tick(4);
    @(negedge clk);
    amiga_reset = 0;
    probe_done(1);
    check_identify(1, 7000, 64, 4, 17, 0);

    // Cold reset invalidates retained RAM; commands cannot use it before a new mount/probe.
    @(negedge clk);
    reset = 1;
    tick(4);
    @(negedge clk);
    reset = 0;
    before_requests = requests;
    issue(8'hec, 1, 0, 1);
    idle;
    if (dut.present !== 0 || !backend.error || requests != before_requests)
      $fatal(1, "cold reset exposed retained RAM");
    mount_image(1, 512 * 8000);
    probe_done(1);
    check_identify(1, 8000, 64, 4, 17, 0);

    // An accepted SD read may outlive the IDE timeout. Complete the ATA error
    // once, retain transport ownership until it drains, then allow a new command.
    @(negedge clk);
    stall_transport = 1;
    issue(8'h20, 1, 1, 1);
    wait (busy);
    tick(20100);
    #1;
    if (dut.state != dut.IDLE || metadata[9] || drq || !backend.error || backend.tfr[1] != 8'h40)
      $fatal(1, "read timeout failed to finish ATA error state=%0d meta=%h", dut.state, metadata);
    if (dut.owner != dut.OWN_HDD || !busy)
      $fatal(1, "timeout released an undrained SD transaction");
    @(negedge clk);
    stall_transport = 0;
    idle;
    check_identify(1, 8000, 64, 4, 17, 0);

    // A guest that never supplies write data must lose DRQ and BSY on timeout.
    before_requests = requests;
    issue(8'h30, 1, 2, 1);
    await_drq;
    tick(20100);
    #1;
    if (dut.state != dut.IDLE || metadata[9] || drq || !backend.error || backend.tfr[1] != 8'h40)
      $fatal(1, "write-data timeout failed to finish ATA error state=%0d meta=%h", dut.state, metadata);
    if (requests != before_requests) $fatal(1, "write-data timeout started an SD transaction");
    check_identify(1, 8000, 64, 4, 17, 0);
    $display("PASS storage: IDE/FIFO, bounds, CHS, multiple mode, arbitration, reset, remount, geometry RAM, timeout");
    $finish;
  end
  initial begin
    #60000000;
    $fatal(1, "global timeout state=%0d", dut.state);
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
