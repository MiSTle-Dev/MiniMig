// Behavioral SDR SDRAM model adapted from snestang/src/verilator/sdr_chip_model.v.
// DATA_WIDTH=16: 32 MiB (4 x 8192 rows x 512 columns), as on both IcePi variants.
// CASDELAY counts clock edges after the READ edge, matching the reference model:
// READ at N, CASDELAY=2 -> data after N+2. The FPGA controller is unchanged.
// Add sequential read bursts for MiniMig; writes remain single-word as configured by the controller.
module sdr_chip_model #(
    parameter DATA_WIDTH = 16,
    parameter ROW_WIDTH  = DATA_WIDTH == 16 ? 13 : 11,
    parameter COL_WIDTH  = DATA_WIDTH == 16 ? 9 : 8,
    parameter CASDELAY   = 2
) (
    input clk,
    inout [DATA_WIDTH-1:0] dq,
    input [ROW_WIDTH-1:0] addr,
    input [DATA_WIDTH/8-1:0] dqm,
    input [1:0] ba,
    input cs_n,
    input ras_n,
    input cas_n,
    input we_n
);
  /* verilator no_inline_module */
  localparam WORD_ADDR_WIDTH = 2 + ROW_WIDTH + COL_WIDTH;
  localparam WORD_COUNT = 1 << WORD_ADDR_WIDTH;
  reg [DATA_WIDTH-1:0] mem[0:WORD_COUNT-1]  /* verilator public_flat_rw */;
  reg [ROW_WIDTH-1:0] row[0:3];
  wire [WORD_ADDR_WIDTH-1:0] col_addr = {ba, row[ba], addr[COL_WIDTH-1:0]};
  wire [2:0] command = {ras_n, cas_n, we_n};
  localparam CMD_ACTIVE = 3'b011;
  localparam CMD_READ = 3'b101;
  localparam CMD_WRITE = 3'b100;
  localparam CMD_LOAD_MODE = 3'b000;
  localparam CMD_BURST_TERMINATE = 3'b110;

  reg [CASDELAY:0] read_valid = 0;
  reg [DATA_WIDTH-1:0] read_data[0:CASDELAY];
  reg [3:0] burst_length = 1;
  reg [3:0] burst_left = 0;
  reg [2:0] burst_index;
  reg [WORD_ADDR_WIDTH-1:0] burst_base;
  wire [2:0] burst_mask = burst_length[2:0] - 3'd1;
  wire [WORD_ADDR_WIDTH-1:0] burst_addr = {
    burst_base[WORD_ADDR_WIDTH-1:3], ((burst_base[2:0] + burst_index) & burst_mask) | (burst_base[2:0] & ~burst_mask)
  };

  always @(posedge clk) begin
    for (integer stage = 1; stage <= CASDELAY; stage = stage + 1) begin
      read_valid[stage] <= read_valid[stage-1];
      read_data[stage]  <= read_data[stage-1];
    end
    read_valid[0] <= 0;
    // Latched burst_base includes its bank and row. An ACTIVE to another bank cannot redirect it.
    if (burst_left != 0) begin
      read_data[0] <= mem[burst_addr];
      read_valid[0] <= 1;
      burst_left <= burst_left - 1'b1;
      burst_index <= burst_index + 1'b1;
    end
    if (!cs_n) begin
      case (command)
        CMD_LOAD_MODE: burst_length <= 4'd1 << addr[2:0];
        CMD_ACTIVE: row[ba] <= addr;
        CMD_READ: begin
          // Consecutive bank-interleaved READs retain the older data already in the CAS pipeline.
          read_data[0] <= mem[col_addr];
          read_valid[0] <= 1;
          burst_base <= col_addr;
          burst_index <= 1;
          burst_left <= burst_length - 1'b1;
        end
        CMD_WRITE: begin
          for (integer byte_index = 0; byte_index < DATA_WIDTH / 8; byte_index = byte_index + 1)
          if (!dqm[byte_index]) mem[col_addr][8*byte_index+:8] <= dq[8*byte_index+:8];
          burst_left <= 0;
        end
        CMD_BURST_TERMINATE: burst_left <= 0;
        default: ;  // NOP, refresh and precharge; timing/refresh retention are not modeled.
      endcase
    end
  end
  assign dq = read_valid[CASDELAY] ? read_data[CASDELAY] : {DATA_WIDTH{1'bz}};
endmodule
// vim: ts=2 sw=2 tw=120 et
