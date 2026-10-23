// NanoMig-style simulation wrapper around the actual stable MiniMig virtual top.
// The native SD controller and Companion image BFM are included; physical PLLs/HDMI are not.
module minimig_tb (
    input clk114,
    input por,
    input reset,
    input [6:0] memory_config,
    input [3:0] cpu_config,
    input [4:0] chipset_config,
    input [3:0] floppy_config,
    input [2:0] ide_config,
    input [7:0] kms_data,
    input [1:0] kms_type,
    input kms_level,
    input [2:0] mouse_buttons,
    output clk28,
    output locked,
    output uart_tx,
    output pwr_led,
    output fdd_led,
    output hdd_led,
    output hs_n,
    output vs_n,
    output [7:0] red,
    green,
    blue,
    output smoke_pass,
    output [31:0] debug_cpu_addr,
    output debug_cpu_reset,
    output [63:0] debug_rom,
    output [15:0] debug_cpu_data,
    output debug_dtack,
    output debug_as,
    output rom_ready,
    output sdclk,
    output sdcmd,
    input sdcmd_in,
    output [3:0] sddat,
    input [3:0] sddat_in,
    input mcu_data_strobe,
    input mcu_data_start,
    input [7:0] mcu_data_in,
    output [7:0] mcu_data_out,
    output mcu_irq,
    input mcu_iack
);
  wire [7:0] image_mounted, sd_rd, sd_wr, read_data, write_data;
  wire [63:0] image_size;
  wire [31:0] sector;
  wire busy, done, error, strobe;
  wire [8:0] addr;
  wire rom_select, rom_accept, rom_available, rom_consume;
  wire [2:0] rom_selected;
  wire [7:0] rom_data;
  wire loading;
  wire [25:2] host_addr;
  wire [31:0] host_data;
  wire host_req, host_ack;
  wire sd_clk114;
  wire [12:0] sdram_a;
  wire [15:0] sdram_dq;
  wire [1:0] sdram_ba, sdram_dqm;
  wire sdram_cs, sdram_ras, sdram_cas, sdram_we, sdram_cke;
  wire rtg_enable;
  wire [6:0] amiga_key;
  keymap keyboard_map (
      .code (kms_data[6:0]),
      .amiga(amiga_key)
  );
  sd_card #(
      .SIMULATE(1),
      .IMAGE_FIFO_BITS(9)
  ) card (
      .clk(clk28),
      .rstn(!por && locked),
      .sdclk(sdclk),
      .sdcmd(sdcmd),
      .sdcmd_in(sdcmd_in),
      .sddat(sddat),
      .sddat_in(sddat_in),
      .data_strobe(mcu_data_strobe),
      .data_start(mcu_data_start),
      .data_in(mcu_data_in),
      .data_out(mcu_data_out),
      .irq(mcu_irq),
      .iack(mcu_iack),
      .image_mounted(image_mounted),
      .image_size(image_size),
      .rstart(sd_rd),
      .wstart(sd_wr),
      .rsector(sector),
      .rbusy(busy),
      .rdone(done),
      .rerror(error),
      .outen(strobe),
      .outaddr(addr),
      .outbyte(read_data),
      .inbyte(write_data),
      .rom_image_selection_strobe(rom_select),
      .rom_image_selected(rom_selected),
      .rom_image_accepted(rom_accept),
      .rom_image_data_available(rom_available),
      .rom_image_data(rom_data),
      .rom_image_data_strobe(rom_consume)
  );
  kickstart_loader rom (
      .clk(clk28),
      .reset(por || !locked),
      .select_strobe(rom_select),
      .selected(rom_selected),
      .image_size(image_size),
      .accepted(rom_accept),
      .available(rom_available),
      .data(rom_data),
      .consume(rom_consume),
      .ready(rom_ready),
      .loading(loading),
      .host_clk(clk114),
      .host_addr(host_addr),
      .host_data(host_data),
      .host_req(host_req),
      .host_ack(host_ack)
  );
  minimig_virtual_top #(
      .havertg(1),
      .haveaudio(0),
      .havec2p(1),
      .haveamigahost(0),
      .ram_64meg(0),
      .usethrottle(0),
      .havecart(0),
      .havevideofilter(0),
      .haveaga(1),
      .haveusbhid(0)
  ) core (
      .CLK_IN(clk114),
      .CLK_USB_IN(1'b0),
      .CLK_RTG_IN(clk28),
      .RESET_N(!por),
      .CLK_114(sd_clk114),
      .CLK_28(clk28),
      .PLL_LOCKED(locked),
      .cfg_cpu(cpu_config),
      .cfg_overclock(1'b0),
      .cfg_memory(memory_config),
      .cfg_chipset(chipset_config),
      .cfg_floppy(floppy_config),
      .cfg_ide(ide_config),
      .cfg_filter(2'b0),
      .cfg_scanline(2'b0),
      .cfg_screen(2'b0),
      .cfg_xoffset(8'd166),
      .cfg_yoffset(8'd47),
      .cfg_reset(reset || !rom_ready),
      .cfg_osd_enable(1'b0),
      .COMP_JOY_SWAP(1'b0),
      .COMP_KMS_LEVEL(kms_level),
      .COMP_KMS_TYPE(kms_type),
      .COMP_KMS_DATA(kms_type == 2 ? {kms_data[7], amiga_key} : kms_data),
      .COMP_MOUSE_BUTTONS(mouse_buttons),
      .COMP_RTC(64'b0),
      .ROM_HOST_ADDR(host_addr),
      .ROM_HOST_DATA(host_data),
      .ROM_HOST_REQ(host_req),
      .ROM_HOST_ACK(host_ack),
      .SDC_IMAGE_MOUNTED(image_mounted),
      .SDC_IMAGE_SIZE(image_size),
      .SDC_RD(sd_rd),
      .SDC_WR(sd_wr),
      .SDC_SECTOR(sector),
      .SDC_WRITE_DATA(write_data),
      .SDC_BUSY(busy),
      .SDC_DONE(done),
      .SDC_ERROR(error),
      .SDC_STROBE(strobe),
      .SDC_ADDR(addr),
      .SDC_READ_DATA(read_data),
      .RTG_ACTIVE(1'b0),
      .RTG_VIDEO_RESET(1'b0),
      .RTG_ENABLE(rtg_enable),
      .HDMI_FRAME_START(1'b0),
      .HDMI_VBLANK_START(1'b0),
      .HDMI_RTG_PIXEL_REQUEST(1'b0),
      .HDMI_RTG_FRAME_REQUEST(1'b0),
      .HDMI_RTG_LINE_PREPARE(1'b0),
      .LED_POWER(pwr_led),
      .LED_FLOPPY(fdd_led),
      .LED_HDD(hdd_led),
      .CTRL_RX(1'b1),
      .AMIGA_RX(1'b1),
      .AMIGA_TX(uart_tx),
      .AMIGA_RESET_N(!reset && rom_ready),
      .AMIGA_KEY(8'b0),
      .AMIGA_KEY_STB(1'b0),
      .C64_KEYS(64'hffffffffffffffff),
      .PS2_DAT_I(1'b1),
      .PS2_CLK_I(1'b1),
      .PS2_MDAT_I(1'b1),
      .PS2_MCLK_I(1'b1),
      .JOYA(7'h7f),
      .JOYB(7'h7f),
      .JOYC(7'h7f),
      .JOYD(7'h7f),
      .FREEZE(1'b0),
      .DVI_HS(hs_n),
      .DVI_VS(vs_n),
      .DVI_R(red),
      .DVI_G(green),
      .DVI_B(blue),
      .SDRAM_A(sdram_a),
      .SDRAM_DQ(sdram_dq),
      .SDRAM_BA(sdram_ba),
      .SDRAM_DQML(sdram_dqm[0]),
      .SDRAM_DQMH(sdram_dqm[1]),
      .SDRAM_nCS(sdram_cs),
      .SDRAM_nRAS(sdram_ras),
      .SDRAM_nCAS(sdram_cas),
      .SDRAM_nWE(sdram_we),
      .SDRAM_CKE(sdram_cke)
  );
  assign smoke_pass = ram.mem[24'h008000] == 16'h1234;
  assign debug_cpu_data = core.tg68_dat_in;
  assign debug_dtack = core.tg68_dtack;
  assign debug_as = core.tg68_as;
  assign debug_cpu_addr = core.tg68_adr;
  assign debug_cpu_reset = core.tg68_rst_sync;
  assign debug_rom = {ram.mem[24'h3c0000], ram.mem[24'h3c0001], ram.mem[24'h3c0002], ram.mem[24'h3c0003]};
  sdr_chip_model #(.CASDELAY(3)) ram (
      .clk(!clk114),
      .dq(sdram_dq),
      .addr(sdram_a),
      .dqm(sdram_dqm),
      .ba(sdram_ba),
      .cs_n(sdram_cs),
      .ras_n(sdram_ras),
      .cas_n(sdram_cas),
      .we_n(sdram_we)
  );
endmodule
// vim: ts=2 sw=2 tw=120 et
