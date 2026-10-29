// Native 128x64 u8g2 bitmap, doubled in both axes and centered in regular PAL.
module mistle_native_osd (
  input clk,
  input reset,

  input enabled,
  input write_en,
  input [10:0] write_addr,
  input [7:0] write_data,

  input pixel_request,
  input frame_request,
  input [7:0] r_in,
  input [7:0] g_in,
  input [7:0] b_in,

  output [7:0] r_out,
  output [7:0] g_out,
  output [7:0] b_out
);

  localparam WIDTH = 256;
  localparam HEIGHT = 128;
  localparam BORDER = 4;
  localparam SHADOW = 8;
  // Requests cover the bitmap, border and shadow: 272x144 pixels.
  reg [8:0] column;
  reg [7:0] row;
  reg pixel_request_d;
  reg frame_valid;
  reg [2:0] window_d, window;

  wire [8:0] request_column = frame_request ? 9'd0 : column;
  wire [7:0] request_row = frame_request ? 8'd0 : row;
  wire signed [9:0] hpos = $signed({1'b0, request_column}) - BORDER;
  wire signed [8:0] vpos = $signed({1'b0, request_row}) - BORDER;

  wire active = hpos >= -BORDER && hpos < WIDTH + BORDER &&
                vpos >= -BORDER && vpos < HEIGHT + BORDER;
  wire tactive = hpos >= 0 && hpos < WIDTH && vpos >= 0 && vpos < HEIGHT;

`ifndef OSD_NO_SHADOW
  wire sactive = hpos >= -BORDER + SHADOW && hpos < WIDTH + BORDER + SHADOW &&
                 vpos >= -BORDER + SHADOW && vpos < HEIGHT + BORDER + SHADOW;
`else
  wire sactive = 1'b0;
`endif

  always @(posedge clk) begin
    if (reset) begin
      pixel_request_d <= 0;
      frame_valid <= 0;
      window_d <= 0;
      window <= 0;
    end else begin
      pixel_request_d <= pixel_request;
      column <= pixel_request ? request_column + 9'd1 : 9'd0;
      if (frame_request) begin
        row <= 0;
        frame_valid <= 1;
      end else if (pixel_request_d && !pixel_request)
        row <= row + 1'b1;
      window_d <= {3{pixel_request && (frame_valid || frame_request)}} & {active, tactive, sactive};
      window <= window_d;
    end
  end

  // The Companion decoder doubles columns for RTG's 256-column bitmap.
  // Native rendering already scales by two, so store each even write once.
  reg [7:0] buffer[1024];

  always @(posedge clk)
    if (write_en && !write_addr[0]) buffer[write_addr[10:1]] <= write_data;

  wire [7:0] hpix = hpos[7:0];
  wire [6:0] vpix = vpos[6:0];
  reg [7:0] buffer_byte;
  reg [2:0] bit_index;
  reg osd_pix;

  // Match the two-cycle request lead to the RAM read and bitmap-bit selection.
  always @(posedge clk) begin
    buffer_byte <= buffer[{vpix[6:4], hpix[7:1]}];
    bit_index <= vpix[3:1];
    osd_pix <= buffer_byte[bit_index];
  end

  wire [7:0] osd_r = (window[1] && osd_pix) ? 8'hff :
                     window[0] ? {4'b0000, r_in[7:4]} : {3'b000, r_in[7:3]};
  wire [7:0] osd_g = (window[1] && osd_pix) ? 8'hff :
                     window[0] ? {4'b0000, g_in[7:4]} : {3'b000, g_in[7:3]};
  wire [7:0] osd_b = (window[1] && osd_pix) ? 8'hff :
                     window[0] ? {4'b0100, b_in[7:4]} : {3'b010, b_in[7:3]};

  wire visible = enabled && !reset;

  assign r_out = !visible ? r_in : window[2] ? osd_r : window[0] ? {1'b0, r_in[7:1]} : r_in;
  assign g_out = !visible ? g_in : window[2] ? osd_g : window[0] ? {1'b0, g_in[7:1]} : g_in;
  assign b_out = !visible ? b_in : window[2] ? osd_b : window[0] ? {1'b0, b_in[7:1]} : b_in;

endmodule
