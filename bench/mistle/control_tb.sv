`timescale 1ns / 1ps
module control_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg reset = 1;
  reg csn = 1, sck = 0, din = 0;
  wire dout, start, sys_strobe, hid_strobe, osd_strobe, sd_strobe;
  wire [7:0] data, sys_reply;
  mcu_spi spi (
      .clk(clk),
      .reset(reset),
      .spi_io_ss(csn),
      .spi_io_clk(sck),
      .spi_io_din(din),
      .spi_io_dout(dout),
      .mcu_sys_strobe(sys_strobe),
      .mcu_hid_strobe(hid_strobe),
      .mcu_osd_strobe(osd_strobe),
      .mcu_sdc_strobe(sd_strobe),
      .mcu_start(start),
      .mcu_dout(data),
      .mcu_sys_din(sys_reply),
      .mcu_hid_din(8'h11),
      .mcu_osd_din(8'h22),
      .mcu_sdc_din(8'h33)
  );
  wire [1:0] cpu, chipmem, slowmem, fastmem, floppy_drives, screen, filter, scanline;
  wire [2:0] turbo, chipset;
  wire overclock, system_reset, video_mode, floppy_wrprot, floppy_turbo, ide_enable;
  wire [7:0] xoffset, yoffset;
  wire [1:0] core_audio_filter, core_autofire;
  wire [7:0] core_xoffset, core_yoffset;
  wire core_reset;
  sysctrl #(
      .AGA(1)
  ) control (
      .clk(clk),
      .reset(reset),
      .data_in_strobe(sys_strobe),
      .data_in_start(start),
      .data_in(data),
      .data_out(sys_reply),
      .int_in(8'b0),
      .buttons(2'b11),
      .system_cpu(cpu),
      .system_overclock(overclock),
      .system_reset(system_reset),
      .system_chipmem(chipmem),
      .system_slowmem(slowmem),
      .system_fastmem(fastmem),
      .system_turbo(turbo),
      .system_chipset(chipset),
      .system_video_mode(video_mode),
      .system_floppy_drives(floppy_drives),
      .system_floppy_wrprot(floppy_wrprot),
      .system_floppy_turbo(floppy_turbo),
      .system_ide_enable(ide_enable),
      .system_video_screen(screen),
      .system_video_filter(filter),
      .system_video_scanlines(scanline),
      .system_xoffset(xoffset),
      .system_yoffset(yoffset)
  );
  wire enabled, write_en;
  wire [10:0] write_addr;
  wire [ 7:0] write_data;
  mistle_osd osd (
      .clk(clk),
      .reset(reset),
      .strobe(osd_strobe),
      .start(start),
      .data(data),
      .enabled(enabled),
      .write_en(write_en),
      .write_addr(write_addr),
      .write_data(write_data)
  );
  reg amiga_reset = 1;
  wire [3:0] core_cpu;
  wire [6:0] memory;
  wire core_overclock, key_disable;
  userio_config config_latch (
      .clk(clk),
      .clk7_en(1'b1),
      .reset(amiga_reset),
      .cfg_cpu({turbo[1:0], cpu}),
      .cfg_overclock(overclock),
      .cfg_memory({1'b0, fastmem, slowmem, chipmem}),
      .cfg_chipset({chipset, video_mode, 1'b0}),
      .cfg_floppy({floppy_drives, floppy_wrprot, floppy_turbo}),
      .cfg_ide({2'b11, ide_enable}),
      .cfg_filter(filter),
      .cfg_scanline(scanline),
      .cfg_screen(screen),
      .cfg_xoffset(xoffset),
      .cfg_yoffset(yoffset),
      .cfg_reset(system_reset),
      .cfg_osd_enable(enabled),
      .cpu_config(core_cpu),
      .memory_config(memory),
      .overclock(core_overclock),
      .key_disable(key_disable),
      .audio_filter_mode(core_audio_filter),
      .autofire_config(core_autofire),
      .xoffset(core_xoffset),
      .yoffset(core_yoffset),
      .usrrst(core_reset)
  );
  reg [7:0] bitmap[0:2047];
  integer writes = 0;
  always @(posedge clk)
    if (write_en) begin
      bitmap[write_addr] = write_data;
      writes = writes + 1;
    end
  task byte_send(input [7:0] value);
    for (integer i = 7; i >= 0; i = i - 1) begin
      #40;
      sck = 1;
      din = value[i];
      #40;
      sck = 0;
    end
  endtask
  task byte_receive(output [7:0] value);
    for (integer i = 7; i >= 0; i = i - 1) begin
      #40;
      sck = 1;
      din = 0;
      #40;
      value[i] = dout;
      sck = 0;
    end
  endtask
  reg [7:0] expected_menu[0:2047];
  reg [7:0] menu_byte;
  task set_value(input [7:0] id, input [7:0] value);
    #100;
    csn = 0;
    byte_send(0);
    byte_send(4);
    byte_send(id);
    byte_send(value);
    #100;
    csn = 1;
    #100;
  endtask
  initial begin
    #100;
    reset = 0;
    #100;
    if (memory !== 7'h15 || core_cpu !== 0) $fatal(1, "reset defaults mismatch %h %h", memory, core_cpu);
    for (integer i = 0; i < 4; i = i + 1) begin
      set_value("T", i);
      if (core_cpu[1:0] !== i[1:0]) $fatal(1, "CPU encoding %0d %h", i, core_cpu);
    end
    set_value("O", 1);
    set_value("Z", 1);
    if (core_overclock) $fatal(1, "overclock with partial turbo");
    set_value("Z", 3);
    if (!core_overclock) $fatal(1, "overclock missing");
    set_value("Q", 3);
    set_value("Y", 3);
    set_value("X", 2);
    if (memory !== 7'h3b) $fatal(1, "memory encoding %h", memory);
    amiga_reset = 0;
    set_value("T", 0);
    set_value("Y", 0);
    if (core_cpu[1:0] !== 3 || memory[1:0] !== 3) $fatal(1, "reset-latched config changed live");
    amiga_reset = 1;
    #40;
    if (core_cpu[1:0] !== 0 || memory[1:0] !== 0) $fatal(1, "reset did not apply config");
    set_value("C", 3);
    if (chipset !== 6) $fatal(1, "AGA mapping");
    // Removed settings remain ignored even when sent by an old saved configuration.
    set_value("f", 2);
    set_value("a", 3);
    if (core_audio_filter !== 1 || core_autofire !== 0)
      $fatal(1, "audio filter/autofire are not permanently disabled");
    set_value("R", 0);
    amiga_reset = 0;
    for (integer i = 0; i < 4; i = i + 1) begin
      case (i)
        0: begin set_value("H", 8'h80); set_value("N", 0); end
        1: begin set_value("H", 8'h7f); set_value("N", 127); end
        2: begin set_value("H", 8'hff); set_value("N", 49); end
        3: begin set_value("H", 8'ha6); set_value("N", 47); end
      endcase
      if (core_xoffset !== xoffset || core_yoffset !== yoffset || system_reset || core_reset)
        $fatal(1, "offsets failed to apply live without reset");
    end
    if (core_xoffset !== 166 || core_yoffset !== 47)
      $fatal(1, "offset defaults changed");
    #100;
    csn = 0;
    byte_send(2);
    byte_send(1);
    byte_send(1);
    #100;
    csn = 1;
    #100;
    if (!enabled || !key_disable) $fatal(1, "OSD did not suppress guest input");
    #100;
    csn = 0;
    byte_send(2);
    byte_send(2);
    byte_send(17);
    byte_send(8'h81);
    byte_send(8'h42);
    #100;
    csn = 1;
    #100;
    if (writes != 4 || bitmap[272] !== 8'h81 || bitmap[273] !== 8'h81 || bitmap[274] !== 8'h42 || bitmap[275] !== 8'h42)
      $fatal(1, "Companion tile mapping writes=%0d %h %h", writes, bitmap[272], bitmap[274]);
    #100;
    csn = 0;
    byte_send(2);
    byte_send(1);
    byte_send(0);
    #100;
    csn = 1;
    #100;
    if (enabled || key_disable) $fatal(1, "OSD hide");
    // Read the entire dedicated EBR through the Companion SPI protocol, including padding.
    $readmemh("amiga_xml.hex", expected_menu);
    if (control.AMIGA_MENU_BYTES != 2048 || control.AMIGA_MENU_ADDR_BITS != 11)
      $fatal(1, "menu does not use one full byte-wide EBR");
    csn = 0;
    byte_send(0);
    byte_send(8);
    byte_send(0);  // Prime the synchronous ROM/SPI reply pipeline, as Companion does.
    for (integer i = 0; i < 2048; i = i + 1) begin
      byte_receive(menu_byte);
      if (menu_byte !== expected_menu[i])
        $fatal(1, "menu byte %0d got %h expected %h", i, menu_byte, expected_menu[i]);
    end
    byte_receive(menu_byte);
    if (menu_byte !== expected_menu[0]) $fatal(1, "menu address did not wrap at the EBR boundary");
    #100;
    csn = 1;
    #100;
    csn = 0;
    byte_send(0);
    byte_send(8);
    byte_send(0);
    byte_receive(menu_byte);
    if (menu_byte !== 8'h1f) $fatal(1, "menu read did not restart at gzip header");
    #100;
    csn = 1;
    #100;
    $display("PASS control: SPI, CPUs, configuration, offsets, disabled filter/autofire, OSD, full 2 KiB menu ROM");
    $finish;
  end
  initial begin
    #3000000;
    $fatal(1, "control timeout");
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
