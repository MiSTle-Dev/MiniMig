// Hold each system-clock request across the 28 MHz DSPI transaction.
// Address and return data are bundled with a toggle/acknowledge handshake.
module flash_dspi_reader (
  input clk,
  input flash_clk,
  input reset,
  input [22:0] address,
  input cs,
  output reg [15:0] dout,
  output reg busy,
  output ready,
  output mspi_cs,
  inout mspi_di,
  inout mspi_do,
  inout mspi_wp,
  inout mspi_hold
);
  reg request;
  reg acknowledge;
  reg [22:0] held_address;
  reg [15:0] held_data;
  (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] ready_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] req_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync = 2'b11;
  wire reader_ready, reader_busy;
  wire [15:0] reader_data;
  reg reader_cs;
  localparam IDLE = 0, WAIT_BUSY = 1, WAIT_DATA = 2;
  reg [1:0] state;

  assign ready = ready_sync[1];

  always @(posedge clk) begin
    ack_sync <= {ack_sync[0], acknowledge};
    ready_sync <= {ready_sync[0], reader_ready};
    if (reset) begin
      ack_sync <= 0;
      ready_sync <= 0;
      request <= 0;
      held_address <= 0;
      dout <= 0;
      busy <= 0;
    end else if (!busy) begin
      if (cs && ready) begin
        held_address <= address;
        request <= ~request;
        busy <= 1;
      end
    end else if (ack_sync[1] == request) begin
      dout <= held_data;
      busy <= 0;
    end
  end

  always @(posedge flash_clk or posedge reset) begin
    if (reset) reset_sync <= 2'b11;
    else reset_sync <= {reset_sync[0], 1'b0};
  end

  always @(posedge flash_clk) begin
    req_sync <= {req_sync[0], request};
    reader_cs <= 0;
    if (reset_sync[1]) begin
      req_sync <= 0;
      acknowledge <= 0;
      held_data <= 0;
      reader_cs <= 0;
      state <= IDLE;
    end else begin
      case (state)
        IDLE: if (req_sync[1] != acknowledge && reader_ready) begin
          reader_cs <= 1;
          state <= WAIT_BUSY;
        end
        WAIT_BUSY: if (reader_busy) state <= WAIT_DATA;
        WAIT_DATA: if (!reader_busy) begin
          held_data <= reader_data;
          acknowledge <= req_sync[1];
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

  flash reader (
    .clk(flash_clk),
    .resetn(!reset_sync[1]),
    .ready(reader_ready),
    .address(held_address),
    .cs(reader_cs),
    .dout(reader_data),
    .busy(reader_busy),
    .mspi_cs(mspi_cs),
    .mspi_di(mspi_di),
    .mspi_do(mspi_do),
    .mspi_wp(mspi_wp),
    .mspi_hold(mspi_hold)
  );
endmodule
// vim: ts=2 sw=2 tw=120 et
