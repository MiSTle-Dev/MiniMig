// NanoMig-style 512 KiB flash Kickstart copy into the stable SDRAM host window.
// Companion ROM selection stops this client after any accepted host write has drained.
module flash_boot #(
    parameter integer LONGWORDS = 131072
) (
    input clk,
    input reset,
    input abort,
    input flash_ready,
    input flash_busy,
    input [15:0] flash_data,
    output reg [22:0] flash_address,
    output reg flash_cs,
    output reg [25:2] host_addr,
    output reg [31:0] host_data,
    output reg host_req,
    input host_ack,
    output reg ready,
    output reg quiescent
);
  localparam WAIT_READY = 0, REQUEST = 1, WAIT_BUSY = 2, WAIT_DATA = 3, WAIT_ACK = 4, DRAIN = 5, STOPPED = 6;
  reg [2:0] state;
  reg [16:0] index;
  reg second_word;
  reg [4:0] drain_count;
  always @(posedge clk) begin
    flash_cs <= 0;
    if (reset) begin
      state <= WAIT_READY;
      index <= 0;
      second_word <= 0;
      flash_address <= 23'h200000;  // word address: byte offset 0x400000
      host_addr <= 24'h1e0000;  // byte address 0x780000 in the stable SDRAM map
      host_data <= 0;
      host_req <= 0;
      ready <= 0;
      quiescent <= 0;
      drain_count <= 0;
    end else begin
      case (state)
        WAIT_READY: if (flash_ready) state <= REQUEST;
        REQUEST: begin
          flash_cs <= 1;
          state <= WAIT_BUSY;
        end
        WAIT_BUSY: if (flash_busy) state <= WAIT_DATA;
        WAIT_DATA:
        if (!flash_busy) begin
          if (!second_word) begin
            host_data[31:16] <= flash_data;
            second_word <= 1;
            flash_address <= flash_address + 1'b1;
            state <= REQUEST;
          end else begin
            host_data[15:0] <= flash_data;
            host_req <= 1;
            state <= WAIT_ACK;
          end
        end
        WAIT_ACK:
        if (host_ack) begin
          host_req <= 0;
          drain_count <= 16;
          state <= DRAIN;
        end
        DRAIN:
        if (drain_count != 0) drain_count <= drain_count - 1'b1;
        else if (abort || index == LONGWORDS - 1) begin
          ready <= !abort;
          quiescent <= 1;
          state <= STOPPED;
        end else begin
          index <= index + 1'b1;
          host_addr <= host_addr + 1'b1;
          flash_address <= flash_address + 1'b1;
          second_word <= 0;
          state <= REQUEST;
        end
        default: ;
      endcase
      // Keep address/data stable while SDRAM still owns an accepted transaction.
      if (abort && state != WAIT_ACK && state != DRAIN) begin
        flash_cs <= 0;
        host_req <= 0;
        ready <= 0;
        quiescent <= 1;
        state <= STOPPED;
      end
    end
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
