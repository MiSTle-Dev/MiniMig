// Direct MiSTle configuration; adapted from the stable userio_osd controller.
module userio_config (
    input [3:0] cfg_cpu,
    input cfg_overclock,
    input [6:0] cfg_memory,
    input [4:0] cfg_chipset,
    input [3:0] cfg_floppy,
    input [2:0] cfg_ide,
    input [1:0] cfg_filter,
    input [1:0] cfg_scanline,
    input [1:0] cfg_screen,
    input [7:0] cfg_xoffset,
    input [7:0] cfg_yoffset,
    input cfg_reset,
    input cfg_osd_enable,




    input       clk,        // 28MHz clock
    input       clk7_en,
    input       clk7n_en,
    input       reset,      //reset
    input       c1,         //clk28m domain clock enable
    input       c3,
    input       sol,        //start of video line
    input       sof,        //start of video frame
    input       varbeamen,
    input       rtg_ena,
    input [7:0] osd_ctrl,   //keycode for OSD control (Amiga keyboard codes + additional keys coded as values > 80h)



    output reg osd_enable = 0,  //osd enable

    output reg           key_disable = 0,                // keyboard disable
    output reg  [   1:0] lr_filter = 0,
    output reg  [   1:0] hr_filter = 0,
    output reg  [   6:0] memory_config = 7'b0_00_01_01,
    output reg  [   4:0] chipset_config = 0,
    output reg  [   3:0] floppy_config = 0,
    output reg  [   1:0] scanline = 0,
    output reg  [   1:0] screen_mode = 0,
    output reg  [   7:0] xoffset = 8'd166,
    output reg  [   7:0] yoffset = 8'd48,
    output reg  [   2:0] ide_config0 = 0,                //enable hard disk support
    output reg  [   2:0] ide_config1 = 0,                //enable hard disk support
    output reg  [   3:0] cpu_config = 0,
    output reg           overclock = 0,
    output wire [   1:0] autofire_config,
    output reg           cd32pad = 0,
    output reg           anajoy = 0,
    output reg           invertjoy = 0,
    output wire [   1:0] audio_filter_mode,
    output reg           pwr_led_dim_n = 0,
    output reg           usrrst = 1'b0,
    output reg           cpurst = 1'b1,
    output reg           cpuhlt = 1'b1,
    output wire          fifo_full,
    // host
    output reg           host_cs,
    output wire [24-1:0] host_adr,
    output reg           host_we,
    output reg  [ 2-1:0] host_bs,
    output wire [16-1:0] host_wdat,
    input  wire [16-1:0] host_rdat,
    input  wire          host_ack
);
  // Fixed off: audio filter encoding 1 means Off (0 would mean LED-controlled Auto).
  assign audio_filter_mode = 2'b01;
  assign autofire_config = 2'b00;

  // The Companion owns OSD pixels. This module only latches Amiga configuration.
  always @(posedge clk) begin
    if (clk7_en) begin
      if (reset) begin
        chipset_config <= cfg_chipset;
        ide_config0 <= cfg_ide;
        ide_config1 <= 3'b0;
        cpu_config[1:0] <= cfg_cpu[1:0];
        memory_config[5:0] <= cfg_memory[5:0];
      end
      cpu_config[3:2] <= cfg_cpu[3:2];
      memory_config[6] <= cfg_memory[6];
      overclock <= cfg_overclock && (&cfg_cpu[3:2]);
    end
    osd_enable <= cfg_osd_enable;
    key_disable <= cfg_osd_enable;
    floppy_config <= cfg_floppy;
    lr_filter <= cfg_filter;
    hr_filter <= cfg_filter;
    scanline <= cfg_scanline;
    screen_mode <= cfg_screen;
    xoffset <= cfg_xoffset;
    yoffset <= cfg_yoffset;
    usrrst <= cfg_reset;
    cpurst <= cfg_reset;
    cpuhlt <= cfg_reset;
    host_cs <= 1'b0;
    host_we <= 1'b0;
    host_bs <= 2'b0;
  end

  assign fifo_full = 1'b0;
  assign host_adr  = 24'b0;
  assign host_wdat = 16'b0;
endmodule
// vim: ts=2 sw=2 tw=120 et
