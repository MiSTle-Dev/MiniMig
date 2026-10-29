`timescale 1ns/1ps
module native_osd_tb;
  reg clk = 0;
  always #5 clk = !clk;
  reg reset = 1;
  reg enabled = 0;
  reg write_en = 0;
  reg [10:0] write_addr = 0;
  reg [7:0] write_data = 0;
  reg [10:0] cx = 0;
  reg [9:0] cy = 0;
  reg scanning = 0;
  reg pixel_request = 0, frame_request = 0;
  reg reference_ready = 0;
  wire [10:0] request_x = cx + 11'd3;
  wire [23:0] rgb;
  localparam [23:0] BACKGROUND = 24'hd6a578;

  mistle_native_osd dut (
    .clk(clk), .reset(reset), .enabled(enabled),
    .write_en(write_en), .write_addr(write_addr), .write_data(write_data),
    .pixel_request(pixel_request), .frame_request(frame_request),
    .r_in(BACKGROUND[23:16]), .g_in(BACKGROUND[15:8]), .b_in(BACKGROUND[7:0]),
    .r_out(rgb[23:16]), .g_out(rgb[15:8]), .b_out(rgb[7:0])
  );

  // Match HDMI's registered requests with the board's two-pixel lead.
  always @(posedge clk) begin
    pixel_request <= scanning && request_x >= 228 && request_x < 500 && cy >= 220 && cy < 364;
    frame_request <= scanning && request_x == 228 && cy == 220;
    if (scanning) begin
      cx <= cx == 907 ? 0 : cx + 1'b1;
      if (cx == 907) cy <= cy == 625 ? 0 : cy + 1'b1;
    end
  end

  function [7:0] pattern(input integer address);
    pattern = address[7:0] ^ {address[2:0], address[9:5]} ^ 8'h96;
  endfunction

  task check_pixel;
    reg area, text_area, shadow_area;
    reg [7:0] bitmap_byte;
    reg [23:0] expected_rgb;
    begin
      // Independent reference in absolute PAL active-picture coordinates.
      area = cx >= 228 && cx < 492 && cy >= 220 && cy < 356;
      text_area = cx >= 232 && cx < 488 && cy >= 224 && cy < 352;
`ifndef OSD_NO_SHADOW
      shadow_area = cx >= 236 && cx < 500 && cy >= 228 && cy < 364;
`else
      shadow_area = 0;
`endif
      bitmap_byte = 0;
      if (text_area) bitmap_byte = pattern(((cy - 224) / 16) * 128 + (cx - 232) / 2);
      expected_rgb = BACKGROUND;
      if (enabled && !reset && reference_ready) begin
        if (area) begin
          if (text_area && bitmap_byte[((cy - 224) / 2) % 8]) expected_rgb = 24'hffffff;
          else expected_rgb = shadow_area ? 24'h0d0a47 : 24'h1a144f;
        end else if (shadow_area) expected_rgb = 24'h6b523c;
      end
      if (rgb !== expected_rgb)
        $fatal(1, "PAL pixel (%0d,%0d): got %h expected %h", cx, cy, rgb, expected_rgb);
    end
  endtask

  integer address, frame, pixel;
  initial begin
    // Odd Companion writes must not overwrite the native bitmap.
    for (address = 0; address < 2048; address = address + 1) begin
      @(negedge clk);
      write_en = 1;
      write_addr = address;
      write_data = address[0] ? ~pattern(address / 2) : pattern(address / 2);
    end
    @(negedge clk);
    write_en = 0;
    reset = 0;
    enabled = 1;
    scanning = 1;
    for (frame = 0; frame < 3; frame = frame + 1) begin
      for (pixel = 0; pixel < 908 * 626; pixel = pixel + 1) begin
        @(negedge clk);
        // Exercise reset and disable inside the bitmap on the second frame.
        reset = frame == 1 && cy >= 250 && cy < 260;
        enabled = !(frame != 0 && cy >= 270 && cy < 280);
        if (reset) reference_ready = 0;
        else if (cx == 228 && cy == 220) reference_ready = 1;
        #1;
        check_pixel;
      end
    end
    $display("PASS: native OSD requests, PAL layout, bitmap scale, border, shadow, reset recovery and enable");
    $finish;
  end
endmodule
