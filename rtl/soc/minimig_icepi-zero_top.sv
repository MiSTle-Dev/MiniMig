// MiniMig/MiSTle for IcePi Zero and Zero XL.
// Board/video architecture translated from icepi-zero-minimig's VHDL top.

// board type define
`include "minimig_board.vh"
`include "minimig_defines.vh"

module minimig_icepizero_top #(
    parameter USB_JOYSTICKS = 0
) (
    input clk,
    input usb_rx,
    output mspi_cs,
    inout mspi_di,
    inout mspi_do,
    inout mspi_wp,
    inout mspi_hold,
    input mspi_clk_ts,
    output usb_tx,
    input [1:0] button,
    output [4:0] led,
    output sdram_clk,
    output sdram_csn,
    output [12:0] sdram_a,
    inout [15:0] sdram_dq,
    output sdram_wen,
    output sdram_rasn,
    output sdram_casn,
    output sdram_cke,
    output [1:0] sdram_ba,
    output [1:0] sdram_dqm,
    output sd_clk,
    inout sd_cmd,
    inout [3:0] sd_dat,
    inout [1:0] usb_dp,
    inout [1:0] usb_dn,
    output [1:0] usb_pull_dp,
    output [1:0] usb_pull_dn,
    inout [27:0] gpio,
    output [3:0] gpdi_dp
);
  localparam RTG_PIXEL_HZ = 66000000;
  localparam RTG_PIXELX5_HZ = 5 * RTG_PIXEL_HZ;
  localparam RTG_FRAME_WIDTH = 1344;
  localparam RTG_FRAME_HEIGHT = 806;
  localparam RTG_SCREEN_WIDTH = 1024;
  localparam RTG_SCREEN_HEIGHT = 768;
  localparam RTG_HSYNC_PULSE_START = 24;
  localparam RTG_HSYNC_PULSE_SIZE = 136;
  localparam RTG_VSYNC_PULSE_START = 3;
  localparam RTG_VSYNC_PULSE_SIZE = 6;
  localparam [1:0] RTG_POLARITY_INVERT = 2'b11;
  localparam RTG_CEA_MODE = 0;
  wire [15:0] audio_l;
  wire [15:0] audio_r;
  wire audio_tick;
  wire clk_sys;
  wire clk_28m;
  wire clk_142m;
  wire clk_usb;
  wire clk_rtg_5x;
  wire clk_rtg;
  wire clk_pixel;
  wire clk_tmds;
  wire pll_locked;
  wire auxpll_locked;
  wire rtg_enable;
  wire rtg_active;
  wire [23:0] rtg_rgb;
  wire hdmi_frame_start;
  wire hdmi_vblank_start;
  wire hdmi_rtg_pixel_request;
  wire hdmi_rtg_frame_request;
  wire hdmi_rtg_line_prepare;
  wire hdmi_osd_pixel_request;
  wire hdmi_osd_frame_request;
  wire hdmi_reset;
  wire amiga_reset_n;
  wire [7:0] dvi_red;
  wire [7:0] dvi_green;
  wire [7:0] dvi_blue;
  wire dvi_hsync;
  wire dvi_vsync;
  wire dvi_window;
  wire dvi_pixel;
  wire display_pal;
  wire long_frame;
  wire interlace;
  wire [3:0] auxclks;
  wire led_floppy;
  wire led_hdd;
  wire led_power;
  wire [1:0] led_usb;
  wire [3:0] cfg_cpu;
  wire cfg_overclock;
  wire [6:0] cfg_memory;
  wire [4:0] cfg_chipset;
  wire [3:0] cfg_floppy;
  wire [2:0] cfg_ide;
  wire [1:0] cfg_filter;
  wire [1:0] cfg_scanline;
  wire [1:0] cfg_screen;
  wire [7:0] cfg_xoffset;
  wire [7:0] cfg_yoffset;
  wire cfg_reset;
  wire cfg_osd_enable;
  wire cfg_osd_we;
  wire [10:0] cfg_osd_addr;
  wire [7:0] cfg_osd_data;

  wire [25:2] host_addr;
  wire [31:0] host_data;
  wire host_req, host_ack;
  wire [25:2] companion_host_addr;
  wire [31:0] companion_host_data;
  wire companion_host_req, companion_host_ack;
  wire flash_ready, flash_quiescent, rom_override, rom_memory_ready;
  wire [25:2] flash_host_addr;
  wire [31:0] flash_host_data;
  wire flash_host_req;
  (* ASYNC_REG = "TRUE" *) reg [1:0] flash_abort_sync = 0;
  always @(posedge clk_sys) flash_abort_sync <= {flash_abort_sync[0], rom_override};
  assign host_addr = flash_quiescent ? companion_host_addr : flash_host_addr;
  assign host_data = flash_quiescent ? companion_host_data : flash_host_data;
  assign host_req = flash_quiescent ? companion_host_req : flash_host_req;
  assign companion_host_ack = flash_quiescent && host_ack;
  wire [22:0] flash_address;
  wire [15:0] flash_data;
  wire flash_cs, flash_busy, flash_reader_ready;
  USRMCLK usrmclk (
      .USRMCLKI(clk_28m),
      .USRMCLKTS(mspi_clk_ts)  // 0 = drive clock; retain this dynamic top-level input.
  )  /* synthesis syn_noprune=1 */;
  flash_dspi_reader flash_reader (
      .clk(clk_sys),
      .flash_clk(clk_28m),
      .reset(!rom_memory_ready),
      .ready(flash_reader_ready),
      .address(flash_address),
      .cs(flash_cs),
      .dout(flash_data),
      .busy(flash_busy),
      .mspi_cs(mspi_cs),
      .mspi_di(mspi_di),
      .mspi_do(mspi_do),
      .mspi_wp(mspi_wp),
      .mspi_hold(mspi_hold)
  );
  flash_boot flash_rom (
      .clk(clk_sys),
      .reset(!rom_memory_ready),
      .abort(flash_abort_sync[1]),
      .flash_ready(flash_reader_ready),
      .flash_busy(flash_busy),
      .flash_data(flash_data),
      .flash_address(flash_address),
      .flash_cs(flash_cs),
      .host_addr(flash_host_addr),
      .host_data(flash_host_data),
      .host_req(flash_host_req),
      .host_ack(host_ack && !flash_quiescent),
      .ready(flash_ready),
      .quiescent(flash_quiescent)
  );
  reg spi_alt /* synthesis syn_keep=1 */;
  always @(posedge clk)
    spi_alt <= gpio[17];
  wire [7:0] sd_rd, sd_wr, sd_write_data, sd_read_data, image_mounted;
  wire [63:0] image_size;
  wire [31:0] sd_sector;
  wire sd_busy, sd_done, sd_error, sd_strobe;
  wire [8:0] sd_addr;
  wire [7:0] joy0, joy1, kms_data;
  wire [2:0] mouse_buttons;
  wire kms_level, keyboard_reset;
  wire [ 1:0] kms_type;
  wire [63:0] rtc_data;
  wire spi_dout, irq_n;
  wire [2:0] volume;
  wire stereo_mix;
  wire joy_swap;
  wire [6:0] joya_i = {1'b1, gpio[5], gpio[0], gpio[2], gpio[1], gpio[4], gpio[3]} & ~joy0[6:0];
  wire [6:0] joyb_i = spi_alt ? {1'b1,     1'b1, gpio[6],    1'b1, gpio[7],     1'b1,    1'b1} & ~joy1[6:0] :
                                {1'b1, gpio[11], gpio[6], gpio[8], gpio[7], gpio[10], gpio[9]} & ~joy1[6:0];
  assign gpio[8:0] = 9'bz;
  assign gpio[9] = spi_alt ? spi_dout : 1'bz;
  assign gpio[11:10] = 2'bz;
  assign gpio[12] = 1'b0;
  assign gpio[15:13] = {led_hdd, led_floppy, led_power};
  assign gpio[16] = usb_tx;
  assign gpio[17] = 1'bz;
  assign gpio[20:18] = 3'bz;
  assign gpio[21] = spi_alt ? 1'bz : spi_dout;
  assign gpio[22] = irq_n;
  assign gpio[27:23] = 5'bz;
  assign usb_pull_dp = 2'b0;
  assign usb_pull_dn = 2'b0;
  assign amiga_reset_n = button[0] && gpio[19] && !cfg_reset;
  wire [5:0] db9 = ~{gpio[5], gpio[0], gpio[2], gpio[1], gpio[4], gpio[3]};
  (* ASYNC_REG = "TRUE" *)reg  [2:0] companion_reset_sync = 3'b111;
  always @(posedge clk_28m or negedge pll_locked)
    if (!pll_locked) companion_reset_sync <= 3'b111;
    else companion_reset_sync <= {companion_reset_sync[1:0], 1'b0};
  wire companion_reset = companion_reset_sync[2];
  ODDRX1F ddr_sdramclk (
      .D0(1'b0),
      .D1(1'b1),
      .Q(sdram_clk),
      .SCLK(clk_sys),
      .RST(1'b0)
  );
  mistle_auxpll auxpll (
      .clk_i (clk),
      .clk_o (auxclks),
      .locked(auxpll_locked)
  );
  assign clk_rtg_5x = auxclks[0];
  assign clk_rtg = auxclks[1];
  assign clk_usb = auxclks[2];
  wire spi_csn = spi_alt ?  gpio[8] : gpio[18];
  wire spi_clk = spi_alt ? gpio[11] : gpio[24];
  wire spi_din = spi_alt ? gpio[10] : gpio[25];
  mistle_companion companion (
      .boot_rom_ready(flash_ready),
      .rom_override(rom_override),
      .clk(clk_28m),
      .reset(companion_reset),
      .host_clk(clk_sys),
      .spi_csn(spi_csn),
      .spi_clk(spi_clk),
      .spi_din(spi_din),
      .spi_dout(spi_dout),
      .irq_n(irq_n),
      .buttons({button[1] && gpio[26], button[0] && gpio[19]}),
      .db9(db9),
      .sd_clk(sd_clk),
      .sd_cmd(sd_cmd),
      .sd_dat(sd_dat),
      .cfg_cpu(cfg_cpu),
      .cfg_overclock(cfg_overclock),
      .cfg_memory(cfg_memory),
      .cfg_chipset(cfg_chipset),
      .cfg_floppy(cfg_floppy),
      .cfg_ide(cfg_ide),
      .cfg_filter(cfg_filter),
      .cfg_scanline(cfg_scanline),
      .cfg_screen(cfg_screen),
      .cfg_xoffset(cfg_xoffset),
      .cfg_yoffset(cfg_yoffset),
      .cfg_reset(cfg_reset),
      .cfg_osd_enable(cfg_osd_enable),
      .cfg_osd_we(cfg_osd_we),
      .cfg_osd_addr(cfg_osd_addr),
      .cfg_osd_data(cfg_osd_data),



      .joy_swap(joy_swap),
      .joystick0(joy0),
      .joystick1(joy1),
      .mouse_buttons(mouse_buttons),
      .kms_level(kms_level),
      .kms_type(kms_type),
      .kms_data(kms_data),
      .keyboard_reset(keyboard_reset),
      .rtc_data(rtc_data),
      .host_addr(companion_host_addr),
      .host_data(companion_host_data),
      .host_req(companion_host_req),
      .host_ack(companion_host_ack),
      .sdc_rd(sd_rd),
      .sdc_wr(sd_wr),
      .sdc_sector(sd_sector),
      .sdc_write_data(sd_write_data),
      .image_mounted(image_mounted),
      .image_size(image_size),
      .sdc_busy(sd_busy),
      .sdc_done(sd_done),
      .sdc_error(sd_error),
      .sdc_strobe(sd_strobe),
      .sdc_addr(sd_addr),
      .sdc_read_data(sd_read_data),
      .volume(volume),
      .stereo_mix(stereo_mix)
  );
  minimig_virtual_top #(
      .hostonly(0),
      .havertg(1),
      .haveaudio(0),
      .havec2p(1),
      .haveamigahost(0),
      .ram_64meg(0),
      .usethrottle(0),
      .havecart(0),
      .havevideofilter(0),
      .haveaga(1),
      .haveusbhid(USB_JOYSTICKS)
  ) virtual_top (
      .cfg_cpu(cfg_cpu),
      .cfg_overclock(cfg_overclock),
      .cfg_memory(cfg_memory),
      .cfg_chipset(cfg_chipset),
      .cfg_floppy(cfg_floppy),
      .cfg_ide(cfg_ide),
      .cfg_filter(cfg_filter),
      .cfg_scanline(cfg_scanline),
      .cfg_reset(cfg_reset),
      .cfg_osd_enable(cfg_osd_enable),

      .COMP_JOY_SWAP(joy_swap),
      .COMP_KMS_LEVEL(kms_level),
      .COMP_KMS_TYPE(kms_type),
      .COMP_KMS_DATA(kms_data),
      .COMP_MOUSE_BUTTONS(mouse_buttons),
      .COMP_RTC(rtc_data),
      .ROM_HOST_ADDR(host_addr),
      .ROM_HOST_DATA(host_data),
      .ROM_HOST_REQ(host_req),
      .ROM_HOST_ACK(host_ack),
      .ROM_MEMORY_READY(rom_memory_ready),
      .SDC_IMAGE_MOUNTED(image_mounted),
      .SDC_IMAGE_SIZE(image_size),
      .SDC_RD(sd_rd),
      .SDC_WR(sd_wr),
      .SDC_SECTOR(sd_sector),
      .SDC_WRITE_DATA(sd_write_data),
      .SDC_BUSY(sd_busy),
      .SDC_DONE(sd_done),
      .SDC_ERROR(sd_error),
      .SDC_STROBE(sd_strobe),
      .SDC_ADDR(sd_addr),
      .SDC_READ_DATA(sd_read_data),
      .FREEZE(1'b0),
      .CLK_IN(clk),
      .CLK_USB_IN(clk_usb),
      .CLK_RTG_IN(clk_rtg),
      .RTG_ENABLE(rtg_enable),
      .RTG_ACTIVE(rtg_active),
      .RTG_VIDEO_RESET(hdmi_reset),
      .RTG_RGB(rtg_rgb),
      .HDMI_FRAME_START(hdmi_frame_start),
      .HDMI_VBLANK_START(hdmi_vblank_start),
      .HDMI_RTG_PIXEL_REQUEST(hdmi_rtg_pixel_request),
      .HDMI_RTG_FRAME_REQUEST(hdmi_rtg_frame_request),
      .HDMI_RTG_LINE_PREPARE(hdmi_rtg_line_prepare),

      .CLK_114(clk_sys),
      .CLK_28(clk_28m),
      .CLK_142(clk_142m),
      .PLL_LOCKED(pll_locked),
      .RESET_N(1'b1),
      .LED_POWER(led_power),
      .LED_FLOPPY(led_floppy),
      .LED_HDD(led_hdd),
      .LED_USB(led_usb),
      .AMIGA_TX(),
      .AMIGA_RX(1'b1),
      .DVI_HS(dvi_hsync),
      .DVI_VS(dvi_vsync),
      .DVI_R(dvi_red),
      .DVI_G(dvi_green),
      .DVI_B(dvi_blue),
      .DVI_STROBE(dvi_pixel),
      .DVI_DE(dvi_window),
      .LONG_FRAME(long_frame),
      .DISPLAY_PAL(display_pal),
      .INTERLACE(interlace),
      .SDRAM_DQ(sdram_dq),
      .SDRAM_A(sdram_a),
      .SDRAM_DQML(sdram_dqm[0]),
      .SDRAM_DQMH(sdram_dqm[1]),
      .SDRAM_nWE(sdram_wen),
      .SDRAM_nCAS(sdram_casn),
      .SDRAM_nRAS(sdram_rasn),
      .SDRAM_nCS(sdram_csn),
      .SDRAM_BA(sdram_ba),
      .SDRAM_CKE(sdram_cke),
      .AUDIO_PAULA_L(audio_l),
      .AUDIO_PAULA_R(audio_r),
      .AUDIO_TICK(audio_tick),
      .PS2_DAT_I(1'b1),
      .PS2_CLK_I(1'b1),
      .PS2_MDAT_I(1'b1),
      .PS2_MCLK_I(1'b1),
      .PS2_DAT_O(),
      .PS2_CLK_O(),
      .PS2_MDAT_O(),
      .PS2_MCLK_O(),
      .AMIGA_RESET_N(amiga_reset_n),
      .AMIGA_KEY(8'b0),
      .AMIGA_KEY_STB(1'b0),
      .C64_KEYS(64'hffffffffffffffff),
      .JOYA(joya_i),
      .JOYB(joyb_i),
      .JOYC(7'h7f),
      .JOYD(7'h7f),
      .USB_DP(usb_dp),
      .USB_DN(usb_dn)
  );
  assign led = {led_power, led_floppy, led_hdd, spi_alt ? 2'b11 : led_usb};
  wire [31:0] hdmi_audio_sample;
  wire hdmi_audio_sample_en;
  wire [2:0] tmds;
  wire tmds_clock;
  wire [23:0] native_rgb;
  wire [23:0] rtg_rgb_overlay;
  mistle_native_osd native_osd (
      .clk(clk_28m),
      .reset(companion_reset),
      .enabled(cfg_osd_enable),
      .write_en(cfg_osd_we),
      .write_addr(cfg_osd_addr),
      .write_data(cfg_osd_data),
      .pixel_request(hdmi_osd_pixel_request),
      .frame_request(hdmi_osd_frame_request),
      .r_in(dvi_red),
      .g_in(dvi_green),
      .b_in(dvi_blue),
      .r_out(native_rgb[23:16]),
      .g_out(native_rgb[15:8]),
      .b_out(native_rgb[7:0])
  );
  reg [23:0] native_rgb_r;
  always @(negedge clk_28m)
    native_rgb_r <= native_rgb;
  wire rtg_overlay, rtg_overlay_pixel;
  (* ASYNC_REG = "TRUE" *) reg [1:0] osd_reset_sync = 2'b0;
  always @(posedge clk_rtg or negedge auxpll_locked)
    if (!auxpll_locked) osd_reset_sync <= 2'b0;
    else osd_reset_sync <= {osd_reset_sync[0], 1'b1};
  rtg_osd osd_rtg (
      .clk_write(clk_28m),
      .clk_rtg(clk_rtg),
      .reset_n(osd_reset_sync[1]),
      .video_reset(hdmi_reset || !rtg_active),
      .write_en(cfg_osd_we),
      .write_addr(cfg_osd_addr),
      .write_data(cfg_osd_data),
      .enable(cfg_osd_enable),
      .pixel_request(hdmi_osd_pixel_request),
      .frame_request(hdmi_osd_frame_request),
      .overlay(rtg_overlay),
      .pixel(rtg_overlay_pixel)
  );
  reg [23:0] rtg_rgb_r;
  always @(negedge clk_rtg)
    rtg_rgb_r <= rtg_overlay ?
        {rtg_overlay_pixel ? 2'b11 : 2'b00, rtg_rgb[23:18],
         rtg_overlay_pixel ? 2'b11 : 2'b00, rtg_rgb[15:10],
         rtg_overlay_pixel ? 2'b11 : 2'b10, rtg_rgb[7:2]} : rtg_rgb;
  wire clksel_n = !rtg_active;
  video_clock_control clock_control (
      .clk(clk),
      .clk_pixel(clk_pixel),
      .native_locked(pll_locked),
      .rtg_locked(auxpll_locked),
      .rtg_request(rtg_enable),
      .rtg_active(rtg_active),
      .video_reset(hdmi_reset)
  );
  DCSC #(
      .DCSMODE("NEG")
  ) clkmux_0 (
      .CLK0(clk_142m),
      .CLK1(clk_rtg_5x),
      .SEL0(clksel_n),
      .SEL1(rtg_active),
      .MODESEL(1'b0),
      .DCSOUT(clk_tmds)
  );
  DCSC #(
      .DCSMODE("NEG")
  ) clkmux_1 (
      .CLK0(clk_28m),
      .CLK1(clk_rtg),
      .SEL0(clksel_n),
      .SEL1(rtg_active),
      .MODESEL(1'b0),
      .DCSOUT(clk_pixel)
  );
  wire signed [16:0] mixed_l = stereo_mix ? ($signed(audio_l) >>> 1) + ($signed(audio_r) >>> 1) : $signed(audio_l);
  wire signed [16:0] mixed_r = stereo_mix ? ($signed(audio_r) >>> 1) + ($signed(audio_l) >>> 1) : $signed(audio_r);
  wire signed [19:0] scaled_l = mixed_l * $signed({1'b0, volume});
  wire signed [19:0] scaled_r = mixed_r * $signed({1'b0, volume});
  audio_cdc audio_sync (
      .clk(clk_28m),
      .clk_pixel(clk_pixel),
      .audio_l(scaled_l[17:2]),
      .audio_r(scaled_r[17:2]),
      .sample_en(hdmi_audio_sample_en),
      .sample(hdmi_audio_sample)
  );
  reg dvi_hsync_r;
  reg dvi_vsync_r;
  always @(negedge clk_28m) begin
    dvi_hsync_r <= dvi_hsync;
    dvi_vsync_r <= dvi_vsync;
  end
  wire [23:0] rgb = rtg_active ? rtg_rgb_r : native_rgb_r;
  hdmi #(
      .VIDEO_RATE(28571400),
      .RTG_VIDEO_RATE(RTG_PIXEL_HZ),
      .RTG_FRAME_WIDTH(RTG_FRAME_WIDTH),
      .RTG_FRAME_HEIGHT(RTG_FRAME_HEIGHT),
      .RTG_SCREEN_WIDTH(RTG_SCREEN_WIDTH),
      .RTG_SCREEN_HEIGHT(RTG_SCREEN_HEIGHT),
      .RTG_HSYNC_PULSE_START(RTG_HSYNC_PULSE_START),
      .RTG_HSYNC_PULSE_SIZE(RTG_HSYNC_PULSE_SIZE),
      .RTG_VSYNC_PULSE_START(RTG_VSYNC_PULSE_START),
      .RTG_VSYNC_PULSE_SIZE(RTG_VSYNC_PULSE_SIZE),
      .RTG_POLARITY_INVERT(RTG_POLARITY_INVERT),
      .RTG_CEA_MODE(RTG_CEA_MODE),
      .RTG_REQUEST_LEAD(2),
      .AUDIO_RATE(48000),
      .AUDIO_BIT_WIDTH(16)
  ) hdmi_inst (
      .clk_pixel_x5(clk_tmds),
      .clk_pixel(clk_pixel),
      .reset(hdmi_reset),
      .rtg_en(rtg_active),
      .rtg_pixel_request(hdmi_rtg_pixel_request),
      .rtg_frame_request(hdmi_rtg_frame_request),
      .rtg_line_prepare(hdmi_rtg_line_prepare),
      .osd_pixel_request(hdmi_osd_pixel_request),
      .osd_frame_request(hdmi_osd_frame_request),
      .frame_start_toggle(hdmi_frame_start),
      .vblank_start_toggle(hdmi_vblank_start),
      .pal_mode(display_pal),
      .long_frame(long_frame),
      .interlace(interlace),
      .screen_mode(cfg_screen),
      .vsync_in(dvi_vsync_r),
      .hsync_in(dvi_hsync_r),
      .offset_x(cfg_xoffset),
      .offset_y(cfg_yoffset[6:0]),
      .rgb(rgb),
      .audio_sample_word_0(hdmi_audio_sample[15:0]),
      .audio_sample_word_1(hdmi_audio_sample[31:16]),
      .audio_sample_en(hdmi_audio_sample_en),
      .tmds(tmds),
      .tmds_clock(tmds_clock)
  );
  assign gpdi_dp = {tmds_clock, tmds};
endmodule
// vim: ts=2 sw=2 tw=120 et
