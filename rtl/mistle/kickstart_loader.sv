// Companion ROM upload to the stable core's physical Kickstart SDRAM window.
// The bundled address/data remain stable throughout the request/acknowledge CDC.
module kickstart_loader #(
    parameter integer IDLE_TIMEOUT = 57142857
) (
    input clk,
    input reset,
    input select_strobe,
    input [2:0] selected,
    input [63:0] image_size,
    output accepted,
    input available,
    input [7:0] data,
    output reg consume,
    output reg ready,
    output reg loading,
    input host_clk,
    output reg [25:2] host_addr,
    output reg [31:0] host_data,
    output reg host_req,
    input host_ack
);
  assign accepted = select_strobe && selected == 0 && (image_size == 64'd262144 || image_size == 64'd524288);
  reg [31:0] word_data;
  reg [18:0] byte_count;
  reg [18:0] length;
  reg small_rom;
  reg [1:0] byte_index;
  reg request;
  reg acknowledge;
  reg waiting;
  reg cooldown;
  reg [25:2] word_addr;
  reg [25:0] timeout_count;
  (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] req_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] host_reset_sync;
  reg [4:0] settle;
  reg mirror;
  reg host_busy;

  always @(posedge clk) begin
    ack_sync <= {ack_sync[0], acknowledge};
    consume  <= 0;
    cooldown <= consume;
    if (reset) begin
      request <= 0;
      ready <= 0;
      loading <= 0;
      waiting <= 0;
      byte_index <= 0;
      timeout_count <= 0;
      ack_sync <= 0;
      consume <= 0;
      cooldown <= 0;
      byte_count <= 0;
      length <= 0;
      word_addr <= 0;
      word_data <= 0;
      small_rom <= 0;
    end else if (select_strobe) begin
      // A new selection invalidates the previous ROM even when rejected.
      ready <= 0;
      loading <= accepted;
      byte_index <= 0;
      byte_count <= 0;
      length <= image_size[18:0] - 1'b1;
      small_rom <= image_size == 64'd262144;
      timeout_count <= 0;
      // An old bus transaction drains before the next image can issue a write.
      waiting <= request != ack_sync[1];
    end else if (loading) begin
      if (waiting) begin
        if (ack_sync[1] == request) begin
          waiting <= 0;
          if (byte_count == length) begin
            ready   <= 1;
            loading <= 0;
          end
        end
      end else if (available && !consume && !cooldown) begin
        timeout_count <= 0;
        word_data <= {word_data[23:0], data};
        consume <= 1;
        byte_index <= byte_index + 1'b1;
        if (byte_index == 3) begin
          word_addr <= (26'h0780000 + {7'b0, byte_count[18:2], 2'b00}) >> 2;
          request   <= ~request;
          waiting   <= 1;
        end
        // Keep the final byte count until the last SDRAM acknowledgement.
        if (byte_count != length) byte_count <= byte_count + 1'b1;
      end else if (timeout_count == IDLE_TIMEOUT - 1) begin
        loading <= 0;
        ready   <= 0;
      end else timeout_count <= timeout_count + 1'b1;
    end
  end

  always @(posedge host_clk) begin
    host_reset_sync <= {host_reset_sync[0], reset};
    req_sync <= {req_sync[0], request};
    if (host_reset_sync[1]) begin
      req_sync <= 0;
      acknowledge <= 0;
      host_req <= 0;
      host_busy <= 0;
      settle <= 0;
      mirror <= 0;
      host_addr <= 0;
      host_data <= 0;
    end else if (!host_busy) begin
      if (req_sync[1] != acknowledge) begin
        host_addr <= word_addr;
        host_data <= word_data;
        host_req <= 1;
        host_busy <= 1;
        mirror <= small_rom;
      end
    end else if (host_req) begin
      if (host_ack) begin
        host_req <= 0;
        // SDRAM hostena covers a burst. Wait for its remaining beats and writes.
        settle   <= 5'd16;
      end
    end else if (settle != 0) settle <= settle - 1'b1;
    else if (mirror) begin
      host_addr <= host_addr + 24'h010000;  // +256 KiB, addresses are longwords
      host_req <= 1;
      mirror <= 0;
    end else begin
      acknowledge <= req_sync[1];
      host_busy   <= 0;
    end
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
