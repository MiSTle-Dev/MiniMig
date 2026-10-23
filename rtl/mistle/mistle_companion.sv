// MiSTle FPGA Companion, native SD transport and control for the stable MiniMig core.
module mistle_companion (
    input boot_rom_ready,
    output reg rom_override,
    input clk,
    input reset,
    input host_clk,
    input spi_csn,
    input spi_clk,
    input spi_din,
    output spi_dout,
    output irq_n,
    input [1:0] buttons,
    input [5:0] db9,
    output sd_clk,
    inout sd_cmd,
    inout [3:0] sd_dat,
    output [3:0] cfg_cpu,
    output cfg_overclock,
    output [6:0] cfg_memory,
    output [4:0] cfg_chipset,
    output [3:0] cfg_floppy,
    output [2:0] cfg_ide,
    output [1:0] cfg_filter,
    output [1:0] cfg_scanline,
    output [1:0] cfg_screen,
    output [7:0] cfg_xoffset,
    output [7:0] cfg_yoffset,
    output cfg_reset,
    output cfg_osd_enable,
    output cfg_osd_we,
    output [10:0] cfg_osd_addr,
    output [7:0] cfg_osd_data,
    output joy_swap,
    output [7:0] joystick0,
    output [7:0] joystick1,
    output [2:0] mouse_buttons,
    output kms_level,
    output [1:0] kms_type,
    output [7:0] kms_data,
    output keyboard_reset,
    output [63:0] rtc_data,
    output [25:2] host_addr,
    output [31:0] host_data,
    output host_req,
    input host_ack,
    input [7:0] sdc_rd,
    input [7:0] sdc_wr,
    input [31:0] sdc_sector,
    input [7:0] sdc_write_data,
    output [7:0] image_mounted,
    output [63:0] image_size,
    output sdc_busy,
    output sdc_done,
    output sdc_error,
    output sdc_strobe,
    output [8:0] sdc_addr,
    output [7:0] sdc_read_data,
    output [2:0] volume,
    output stereo_mix
);
  wire sys_strobe, hid_strobe, osd_strobe, sd_strobe, start;
  wire [7:0] data, sys_reply, hid_reply, sd_reply;
  wire [7:0] int_ack;
  wire hid_irq, sd_irq;
  mcu_spi spi (
      .clk(clk),
      .reset(reset),
      .spi_io_ss(spi_csn),
      .spi_io_clk(spi_clk),
      .spi_io_din(spi_din),
      .spi_io_dout(spi_dout),
      .mcu_sys_strobe(sys_strobe),
      .mcu_hid_strobe(hid_strobe),
      .mcu_osd_strobe(osd_strobe),
      .mcu_sdc_strobe(sd_strobe),
      .mcu_start(start),
      .mcu_dout(data),
      .mcu_sys_din(sys_reply),
      .mcu_hid_din(hid_reply),
      .mcu_osd_din(8'h55),
      .mcu_sdc_din(sd_reply)
  );
  wire system_reset;
  wire [1:0] floppy_drives, cpu, chipmem, slowmem, fastmem, screen, filter, scanlines;
  wire floppy_turbo, floppy_wrprot, ide_enable, video_mode, overclock;
  wire [2:0] chipset, turbo;
  wire [11:0] rtc;
  sysctrl #(
      .AGA(1)
  ) control (
      .clk(clk),
      .reset(reset),
      .data_in_strobe(sys_strobe),
      .data_in_start(start),
      .data_in(data),
      .data_out(sys_reply),
      .int_out_n(irq_n),
      .int_in({4'b0, sd_irq, 1'b0, hid_irq, 1'b0}),
      .int_ack(int_ack),
      .buttons(buttons),
      .system_reset(system_reset),
      .system_floppy_drives(floppy_drives),
      .system_floppy_turbo(floppy_turbo),
      .system_floppy_wrprot(floppy_wrprot),
      .system_cpu(cpu),
      .system_chipset(chipset),
      .system_video_mode(video_mode),
      .system_video_screen(screen),
      .system_ide_enable(ide_enable),
      .system_video_filter(filter),
      .system_video_scanlines(scanlines),
      .system_chipmem(chipmem),
      .system_slowmem(slowmem),
      .system_fastmem(fastmem),
      .system_turbo(turbo),
      .system_joy_swap(joy_swap),
      .system_volume(volume),
      .system_stereo_mix(stereo_mix),
      .system_overclock(overclock),
      .system_xoffset(cfg_xoffset),
      .system_yoffset(cfg_yoffset),
      .rtc(rtc)
  );

  wire [7:0] joy0, joy1;
  assign joystick0 = joy0;
  assign joystick1 = joy1;
  hid input_events (
      .clk(clk),
      .reset(reset),
      .data_in_strobe(hid_strobe),
      .data_in_start(start),
      .data_in(data),
      .data_out(hid_reply),
      .db9_port(db9),
      .irq(hid_irq),
      .iack(int_ack[1]),
      .mouse_buttons(mouse_buttons),
      .kbd_mouse_level(kms_level),
      .kbd_mouse_type(kms_type),
      .kbd_mouse_data(kms_data),
      .kbd_reset(keyboard_reset),
      .joystick0(joy0),
      .joystick1(joy1)
  );
  mistle_osd osd (
      .clk(clk),
      .reset(reset),
      .strobe(osd_strobe),
      .start(start),
      .data(data),
      .enabled(cfg_osd_enable),
      .write_en(cfg_osd_we),
      .write_addr(cfg_osd_addr),
      .write_data(cfg_osd_data)
  );
  wire rom_select, rom_accepted, rom_available, rom_consume, rom_ready, rom_loading;
  wire [2:0] rom_selected;
  wire [7:0] rom_data;
  sd_card #(
      .CLK_DIV(3'd2),
      .IMAGE_FIFO_BITS(9)
  ) card (
      .clk(clk),
      .rstn(!reset),
      .sdclk(sd_clk),
      .sdcmd(sd_cmd),
      .sddat(sd_dat),
      .data_strobe(sd_strobe),
      .data_start(start),
      .data_in(data),
      .data_out(sd_reply),
      .irq(sd_irq),
      .iack(int_ack[3]),
      .image_mounted(image_mounted),
      .image_size(image_size),
      .rstart(sdc_rd),
      .wstart(sdc_wr),
      .rsector(sdc_sector),
      .rbusy(sdc_busy),
      .rdone(sdc_done),
      .rerror(sdc_error),
      .inbyte(sdc_write_data),
      .outen(sdc_strobe),
      .outaddr(sdc_addr),
      .outbyte(sdc_read_data),
      .rom_image_selection_strobe(rom_select),
      .rom_image_selected(rom_selected),
      .rom_image_accepted(rom_accepted),
      .rom_image_data_available(rom_available),
      .rom_image_data(rom_data),
      .rom_image_data_strobe(rom_consume)
  );
  kickstart_loader rom (
      .clk(clk),
      .reset(reset),
      .select_strobe(rom_select && (image_size != 0 || !rom_ready)),
      .selected(rom_selected),
      .image_size(image_size),
      .accepted(rom_accepted),
      .available(rom_available),
      .data(rom_data),
      .consume(rom_consume),
      .ready(rom_ready),
      .loading(rom_loading),
      .host_clk(host_clk),
      .host_addr(host_addr),
      .host_data(host_data),
      .host_req(host_req),
      .host_ack(host_ack)
  );
  (* ASYNC_REG = "TRUE" *) reg [1:0] boot_ready_sync;
  always @(posedge clk) begin
    if (reset) begin
      boot_ready_sync <= 0;
      rom_override <= 0;
    end else begin
      boot_ready_sync <= {boot_ready_sync[0], boot_rom_ready};
      if (rom_select && rom_selected == 0 && image_size != 0) rom_override <= 1;
    end
  end
  assign cfg_reset = system_reset || !(rom_ready || (boot_ready_sync[1] && !rom_override)) || rom_loading || keyboard_reset;
  assign cfg_cpu = {turbo[1:0], cpu};
  assign cfg_overclock = overclock && (&turbo[1:0]);
  assign cfg_memory = {1'b0, fastmem, slowmem, chipmem};
  assign cfg_chipset = {chipset, video_mode, 1'b0};
  assign cfg_floppy = {floppy_drives, floppy_wrprot, floppy_turbo};
  assign cfg_filter = filter;
  assign cfg_scanline = scanlines;
  assign cfg_screen = screen;
  // Native primary master/slave remain configurable after media changes.
  assign cfg_ide = {2'b11, ide_enable};
  reg [63:0] rtc_value;
  reg rtc_toggle;
  always @(posedge clk) begin
    if (reset) begin
      rtc_value  <= 64'b0;
      rtc_toggle <= 0;
    end else if (rtc_toggle != rtc[11]) begin
      rtc_toggle <= rtc[11];
      rtc_value[rtc[10:8]*8+:8] <= rtc[7:0];
    end
  end
  assign rtc_data = rtc_value;
endmodule
// vim: ts=2 sw=2 tw=120 et
