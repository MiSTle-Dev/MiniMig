// Decode the existing Companion u8g2 tile protocol into the stable 256x64 OSD.
// Companion tiles are 128x64; duplicate columns to retain the native/RTG layout.
module mistle_osd (
    input clk,
    input reset,
    input strobe,
    input start,
    input [7:0] data,
    output reg enabled,
    output reg write_en,
    output reg [10:0] write_addr,
    output reg [7:0] write_data
);
  reg [7:0] command;
  reg address_pending;
  reg [9:0] address;
  reg duplicate;
  always @(posedge clk) begin
    write_en  <= 0;
    duplicate <= 0;
    if (reset) begin
      enabled <= 0;
      command <= 0;
      address_pending <= 0;
      address <= 0;
      write_en <= 0;
      write_addr <= 0;
      write_data <= 0;
    end else begin
      if (duplicate) begin
        write_en   <= 1;
        write_addr <= write_addr + 1'b1;
      end
      if (strobe) begin
        if (start) begin
          command <= data;
          address_pending <= 1;
        end else if (address_pending) begin
          address_pending <= 0;
          if (command == 1) enabled <= data[0];
          if (command == 2) address <= {data[6:0], 3'b0};
        end else if (command == 2) begin
          write_en <= 1;
          write_addr <= {address, 1'b0};
          write_data <= data;
          address <= address + 1'b1;
          duplicate <= 1;
        end
      end
    end
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
