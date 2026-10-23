// IDE image/sector controller extracted and adapted from NanoMig/src/nanomig.v.
// NanoMig contributors retain their original copyright and license; see doc/PROVENANCE.md.
// The media/geometry and ATA work previously embedded in nanomig is independent of CPU/video here.
// Unlike NanoMig's management registers, the client bus is the stable MiniMig HDD/FIFO interface.
module sdc_controller #(
    parameter integer TIMEOUT_CYCLES = 57142857
) (
    input clk,
    input reset,
    input amiga_reset,
    input [7:0] image_mounted,
    input [63:0] image_size,
    input hdd_cmd_req,
    input hdd_dat_req,
    input [15:0] hdd_data_in,
    input [15:0] hdd_metadata,
    output reg [2:0] hdd_addr,
    output reg [15:0] hdd_data_out,
    output hdd_wr,
    output hdd_status_wr,
    output hdd_data_wr,
    output hdd_data_rd,
    input [3:0] fdc_rd,
    input [3:0] fdc_wr,
    input [31:0] fdc_sector,
    input [7:0] fdc_write_data,
    output fdc_busy,
    output fdc_done,
    output fdc_strobe,
    output [7:0] sd_rd,
    output [7:0] sd_wr,
    output [31:0] sd_sector,
    input sd_busy,
    input sd_done,
    input sd_error,
    input sd_strobe,
    input [8:0] sd_addr,
    input [7:0] sd_read_data,
    output [7:0] sd_write_data
);
  // Per-drive state fixes NanoMig's concurrent initialization and drive-0 geometry assumptions.
  reg [1:0] mounted;
  reg [1:0] examined;
  reg [1:0] present;
  reg active_drive;
  // Reset validity, not payload. One write port and an asynchronous drive-select read
  // allow this small table to use slice distributed RAM instead of payload registers.
  reg [57:0] media_info[0:1] /* synthesis syn_ramstyle="distributed" */;
  wire [57:0] active_info = media_info[active_drive];
  wire [28:0] capacity = active_info[57:29];  // Includes a count of 2^28 sectors.
  wire [15:0] cylinders = active_info[28:13];
  wire [4:0] heads = active_info[12:8];
  wire [7:0] sectors = active_info[7:0];
  reg [4:0] multiple[0:1];
  reg [5:0] generation;
  reg [7:0] taskfile[1:7];
  reg [31:0] lba;
  reg [8:0] remaining;
  reg [4:0] block_left;
  reg [4:0] block_size;
  reg writing;
  reg [7:0] command;
  reg [7:0] error_code;
  reg [7:0] status_value;
  reg [25:0] timer;
  reg [7:0] word_index;
  reg [8:0] buffer_addr;
  reg [7:0] buffer[0:511]  /* synthesis syn_ramstyle="block_ram" */;
  reg [7:0] buffer_read;
  reg [15:0] fifo_word;
  reg [15:0] identify_word;
  reg [31:0] rdb_signature;
  reg [15:0] parsed_cylinders, parsed_heads, parsed_sectors;
  reg sector_request;
  reg sector_write;
  reg [31:0] request_sector;
  reg request_complete;
  reg request_error;
  reg [2:0] owner;
  localparam OWN_IDLE = 0, OWN_HDD = 1, OWN_FDC = 2;
  reg transport_started;
  reg [7:0] selected_rd, selected_wr;
  reg [31:0] selected_sector;
  reg transport_turn;
  wire selected_hdd = owner == OWN_HDD;
  assign sd_rd = !transport_started ? selected_rd : 8'b0;
  assign sd_wr = !transport_started ? selected_wr : 8'b0;
  assign sd_sector = selected_sector;
  assign sd_write_data = selected_hdd ? buffer_read : fdc_write_data;
  // Present busy while another client owns the bus, even before transport accepts it.
  assign fdc_busy = owner == OWN_HDD || sd_busy;
  assign fdc_done = owner == OWN_FDC && sd_done;
  assign fdc_strobe = owner == OWN_FDC && sd_strobe;

  wire sector_buffer_write = owner == OWN_HDD && transport_started && sd_strobe && !sector_write;
  wire buffer_write = sector_buffer_write || state == BUFFER_LOW || state == BUFFER_HIGH;
  wire [8:0] buffer_write_addr = sector_buffer_write ? sd_addr : buffer_addr;
  wire [7:0] buffer_write_data = sector_buffer_write ? sd_read_data :
                               state == BUFFER_LOW ? fifo_word[15:8] : fifo_word[7:0];
  // A single synchronous read and a single write port map this shared 512-byte buffer to one EBR.
  always @(posedge clk) begin
    if (buffer_write) buffer[buffer_write_addr] <= buffer_write_data;
    buffer_read <= buffer[owner==OWN_HDD&&transport_started?sd_addr : buffer_addr];
  end
  always @(posedge clk) begin
    request_complete <= 0;
    request_error <= 0;
    if (reset) begin
      owner <= OWN_IDLE;
      transport_started <= 0;
      selected_rd <= 0;
      selected_wr <= 0;
      selected_sector <= 0;
      transport_turn <= 0;
    end else if (owner == OWN_IDLE) begin
      selected_rd <= 0;
      selected_wr <= 0;
      if (!sd_busy) begin
        if (sector_request && !amiga_reset && (state == PROBE_WAIT || !cancelled) && (!(|fdc_rd || |fdc_wr) || !transport_turn)) begin
          owner <= OWN_HDD;
          selected_sector <= request_sector;
          selected_rd <= sector_write ? 8'b0 : (active_drive ? 8'h20 : 8'h10);
          selected_wr <= sector_write ? (active_drive ? 8'h20 : 8'h10) : 8'b0;
          transport_started <= 0;
          transport_turn <= 1;
        end else if (|fdc_rd || |fdc_wr) begin
          owner <= OWN_FDC;
          selected_sector <= fdc_sector;
          // A single drive owns each transaction, including contradictory/multiple requests.
          selected_wr <= {4'b0, fdc_wr & (~fdc_wr + 4'b1)};
          selected_rd <= |fdc_wr ? 8'b0 : {4'b0, fdc_rd & (~fdc_rd + 4'b1)};
          transport_started <= 0;
          transport_turn <= 0;
        end
      end
    end else begin
      if (sd_busy) transport_started <= 1;
      if (transport_started && sd_done) begin
        if (owner == OWN_HDD) begin
          request_complete <= 1;
          request_error <= sd_error;
        end
        owner <= OWN_IDLE;
        selected_rd <= 0;
        selected_wr <= 0;
        transport_started <= 0;
      end
    end
  end

  localparam IDLE=0, GET_REGS=1, DECODE=2, STATUS=3, STATUS_GAP=4,
    SECTOR_START=5, SECTOR_WAIT=6, READ_ADDR=7, READ_BYTE=8, READ_WORD=9,
    FIFO_WRITE=10, FIFO_GAP=11, WAIT_READ=12, WAIT_WRITE=13, FIFO_CAPTURE=14,
    FIFO_POP=15, FIFO_POP_GAP=16, BUFFER_LOW=17, BUFFER_HIGH=18,
    WRITE_COMPLETE=19, ERROR_REG=20, ERROR_GAP=21, IDENTIFY=22,
    IDENTIFY_GAP=23, PROBE_START=24, PROBE_WAIT=25, PROBE_PARSE=26,
    PROBE_GAP=27, PROBE_FINISH=28, COMPLETE=29, READ_LOW=30;
  reg [5:0] state;
  reg [5:0] after_status;
  wire live_command = hdd_metadata[9] && hdd_metadata[15:10] == generation && hdd_metadata[8] == 0;
  wire cancelled = amiga_reset || !live_command;
  wire service_state = state != IDLE && state < PROBE_START || state == COMPLETE || state == READ_LOW;
  wire mount_event = |image_mounted[5:4];
  wire valid_geometry = rdb_signature == "RDSK" && parsed_heads != 0 && parsed_heads <= 16 &&
                        parsed_sectors != 0 && parsed_sectors <= 255 && parsed_cylinders != 0;
  wire probe_commit = state == PROBE_FINISH && valid_geometry && !mount_event &&
                      !amiga_reset && {6'b0, timer} != TIMEOUT_CYCLES;
  // sd_card emits a one-hot image_mounted pulse with one shared image_size payload.
  // Mounts win over probes; a probe for the other drive waits until this port is free.
  always @(posedge clk) begin
    if (!reset) begin
      if (mount_event)
        media_info[image_mounted[5]] <= {image_size[37:9], 29'b0};
      else if (probe_commit)
        media_info[active_drive] <= {capacity, parsed_cylinders, parsed_heads[4:0], parsed_sectors[7:0]};
    end
  end
  assign hdd_wr = state == ERROR_REG && !cancelled;
  assign hdd_status_wr = state == STATUS && !cancelled;
  assign hdd_data_wr = (state == FIFO_WRITE || state == IDENTIFY) && !cancelled;
  assign hdd_data_rd = state == FIFO_POP && !cancelled;
  // The stable IDE backend uses rising/falling strobes, unlike NanoMig's address-15 access.
  always @* begin
    hdd_addr = 7;
    hdd_data_out = 0;
    if (state == GET_REGS) hdd_addr = word_index[2:0];
    if (state == STATUS) hdd_data_out = {8'b0, status_value};
    if (state == ERROR_REG) begin
      hdd_addr = 1;
      hdd_data_out = {8'b0, error_code};
    end
    if (state == FIFO_WRITE || state == FIFO_CAPTURE || state == FIFO_POP ||
        state == FIFO_POP_GAP || state == IDENTIFY || state == IDENTIFY_GAP) begin
      hdd_addr = 0;
      hdd_data_out = state == IDENTIFY ? identify_word : fifo_word;
    end
  end
  // IDENTIFY reports the entire image, not geometry rounded down to cylinders.
  // Disk data is little-endian words on the stable Amiga FIFO, as in NanoMig.
  reg [15:0] identify_native;
  always @* begin
    identify_native = 0;
    case (word_index)
      0: identify_native = 16'h0040;
      1: identify_native = cylinders;
      3: identify_native = {11'b0, heads};
      6: identify_native = {8'b0, sectors};
      47: identify_native = 16'h8010;
      49: identify_native = 16'h0200;
      53: identify_native = 16'h0001;
      54: identify_native = cylinders;
      55: identify_native = {11'b0, heads};
      56: identify_native = {8'b0, sectors};
      57: identify_native = capacity[15:0];
      58: identify_native = {3'b0, capacity[28:16]};
      59: identify_native = {7'b0, multiple[active_drive] != 0, 3'b0, multiple[active_drive]};
      60: identify_native = capacity[15:0];
      61: identify_native = {3'b0, capacity[28:16]};
      27: identify_native = "Mi";
      28: identify_native = "ST";
      29: identify_native = "le";
      30: identify_native = " H";
      31: identify_native = "DF";
      default: if (word_index >= 10 && word_index <= 46) identify_native = 16'h2020;
    endcase
    identify_word = {identify_native[7:0], identify_native[15:8]};
  end
  wire [31:0] task_lba = taskfile[6][6] ?
    {4'b0, taskfile[6][3:0], taskfile[5], taskfile[4], taskfile[3]} :
    (({taskfile[5], taskfile[4]} * heads + taskfile[6][3:0]) *
      sectors + {24'b0, taskfile[3]} - 1'b1);
  wire [8:0] task_count = taskfile[2] == 0 ? 9'd256 : {1'b0, taskfile[2]};
  integer drive;
  always @(posedge clk) begin
    if (reset) begin
      mounted <= 0;
      examined <= 0;
      present <= 0;
      state <= IDLE;
      sector_request <= 0;
      sector_write <= 0;
      timer <= 0;
      word_index <= 0;
      active_drive <= 0;
      generation <= 0;
      buffer_addr <= 0;
      fifo_word <= 0;
      lba <= 0;
      remaining <= 0;
      block_left <= 0;
      block_size <= 0;
      writing <= 0;
      command <= 0;
      status_value <= 0;
      after_status <= IDLE;
      error_code <= 0;
      request_sector <= 0;
      rdb_signature <= 0;
      parsed_cylinders <= 0;
      parsed_heads <= 0;
      parsed_sectors <= 0;
      for (drive = 0; drive < 2; drive = drive + 1) begin
        multiple[drive] <= 0;
      end
    end else begin
      if (owner == OWN_HDD && sd_busy) sector_request <= 0;
      if (state == IDLE || state == STATUS || state == FIFO_WRITE || state == FIFO_POP || sd_strobe || request_complete)
        timer <= 0;
      else if (timer != TIMEOUT_CYCLES) timer <= timer + 1'b1;

      case (state)
        IDLE: begin
          if (!amiga_reset && owner == OWN_IDLE && !sd_busy) begin
            if ((mounted & ~examined) != 0) begin
              active_drive <= mounted[0] && !examined[0] ? 0 : 1;
              state <= PROBE_START;
            end else if (hdd_cmd_req) begin
              generation <= hdd_metadata[15:10];
              active_drive <= 0;  // drive selection is captured with taskfile register 6
              word_index <= 1;
              state <= GET_REGS;
            end
          end
        end
        GET_REGS: begin
          taskfile[word_index[2:0]] <= hdd_data_in[7:0];
          if (word_index == 7) begin
            active_drive <= taskfile[6][4];
            state <= DECODE;
          end else word_index <= word_index + 1'b1;
        end
        DECODE: begin
          command <= taskfile[7];
          lba <= task_lba;
          remaining <= task_count;
          block_size <= taskfile[7] == 8'hc4 || taskfile[7] == 8'hc5 ? multiple[active_drive] : 1;
          block_left <= taskfile[7] == 8'hc4 || taskfile[7] == 8'hc5 ?
                        (task_count < multiple[active_drive] ? task_count[4:0] : multiple[active_drive]) : 1;
          error_code <= 8'h04;  // ABRT for unsupported commands or invalid multiple mode.
          status_value <= 8'hd1;
          after_status <= IDLE;
          state <= ERROR_REG;
          if (present[active_drive] && !hdd_metadata[8]) begin
            case (taskfile[7])
              8'hec: begin
                word_index <= 0;
                status_value <= 8'h08;
                after_status <= IDENTIFY;
                state <= STATUS;
              end
              8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
              8'h18, 8'h19, 8'h1a, 8'h1b, 8'h1c, 8'h1d, 8'h1e, 8'h1f,
              8'h91, 8'he7, 8'hea: begin
                status_value <= 8'h90;
                state <= STATUS;
              end
              8'hc6: begin
                if (taskfile[2] == 0 || taskfile[2] == 1 || taskfile[2] == 2 ||
                    taskfile[2] == 4 || taskfile[2] == 8 || taskfile[2] == 16) begin
                  multiple[active_drive] <= taskfile[2][4:0];
                  status_value <= 8'h90;
                  state <= STATUS;
                end
              end
              8'h20, 8'h21, 8'h30, 8'h31, 8'hc4, 8'hc5: begin
                if ((taskfile[7] != 8'hc4 && taskfile[7] != 8'hc5) || multiple[active_drive] != 0) begin
                  if (task_lba < {3'b0, capacity} && task_count <= {3'b0, capacity} - task_lba &&
                      (taskfile[6][6] || (taskfile[3] != 0 && taskfile[3] <= sectors &&
                       {1'b0, taskfile[6][3:0]} < heads))) begin
                    writing <= taskfile[7] == 8'h30 || taskfile[7] == 8'h31 || taskfile[7] == 8'hc5;
                    status_value <= taskfile[7] == 8'h30 || taskfile[7] == 8'h31 || taskfile[7] == 8'hc5 ?
                                    8'h04 : 8'h08;
                    after_status <= taskfile[7] == 8'h30 || taskfile[7] == 8'h31 || taskfile[7] == 8'hc5 ?
                                    WAIT_WRITE : SECTOR_START;
                    state <= STATUS;
                  end else error_code <= 8'h10;  // IDNF
                end
              end
              default: ;
            endcase
          end
        end
        STATUS: state <= STATUS_GAP;
        STATUS_GAP: state <= after_status;
        ERROR_REG: state <= ERROR_GAP;
        ERROR_GAP: state <= STATUS;
        IDENTIFY: begin
          state <= IDENTIFY_GAP;
        end
        IDENTIFY_GAP: begin
          if (word_index == 255) begin
            status_value <= 8'h90;
            after_status <= IDLE;
            state <= STATUS;
          end else begin
            word_index <= word_index + 1'b1;
            state <= IDENTIFY;
          end
        end
        SECTOR_START: begin
          request_sector <= lba;
          sector_write <= writing;
          sector_request <= 1;
          state <= SECTOR_WAIT;
        end
        SECTOR_WAIT:
        if (request_complete) begin
          if (request_error) begin
            error_code <= 8'h40;
            status_value <= 8'hd1;
            after_status <= IDLE;
            state <= ERROR_REG;
          end else if (writing) state <= WRITE_COMPLETE;
          else begin
            buffer_addr <= 0;
            word_index <= 0;
            state <= READ_ADDR;
          end
        end
        READ_ADDR: state <= READ_BYTE;
        READ_BYTE: begin
          fifo_word[15:8] <= buffer_read;
          buffer_addr <= buffer_addr + 1'b1;
          state <= READ_WORD;
        end
        READ_WORD: state <= READ_LOW;
        READ_LOW: begin
          // RDB/HDF bytes are big-endian on the Amiga-facing stable FIFO.
          fifo_word[7:0] <= buffer_read;
          state <= FIFO_WRITE;
        end
        FIFO_WRITE: state <= FIFO_GAP;
        FIFO_GAP: begin
          buffer_addr <= buffer_addr + 1'b1;
          word_index  <= word_index + 1'b1;
          if (word_index == 255) begin
            remaining <= remaining - 1'b1;
            block_left <= block_left - 1'b1;
            lba <= lba + 1'b1;
            if (block_left == 1) begin
              status_value <= 8'h18;
              after_status <= WAIT_READ;
              state <= STATUS;
            end else state <= SECTOR_START;
          end else state <= READ_ADDR;
        end
        WAIT_READ: begin
          if (remaining == 0) begin
            // Final read completion is also generated by the stable core when drained.
            state <= COMPLETE;
          end else if (hdd_cmd_req) begin
            block_left <= remaining < block_size ? remaining[4:0] : block_size;
            state <= SECTOR_START;
          end
        end
        COMPLETE: begin
          if (!hdd_metadata[9]) state <= IDLE;
        end
        WAIT_WRITE:
        if (hdd_dat_req) begin
          word_index <= 0;
          buffer_addr <= 0;
          state <= FIFO_POP_GAP;
        end
        FIFO_POP_GAP: state <= FIFO_CAPTURE;
        FIFO_CAPTURE: begin
          fifo_word <= hdd_data_in;
          state <= FIFO_POP;
        end
        FIFO_POP: state <= BUFFER_LOW;
        BUFFER_LOW: begin
          buffer_addr <= buffer_addr + 1'b1;
          state <= BUFFER_HIGH;
        end
        BUFFER_HIGH: begin
          buffer_addr <= buffer_addr + 1'b1;
          if (word_index == 255) state <= SECTOR_START;
          else begin
            word_index <= word_index + 1'b1;
            state <= FIFO_POP_GAP;
          end
        end
        WRITE_COMPLETE: begin
          remaining <= remaining - 1'b1;
          block_left <= block_left - 1'b1;
          lba <= lba + 1'b1;
          if (remaining == 1) begin
            status_value <= 8'h90;
            after_status <= IDLE;
            state <= STATUS;
          end else if (block_left == 1) begin
            status_value <= 8'h10;
            after_status <= WAIT_WRITE;
            block_left <= remaining - 1 < block_size ? remaining[4:0] - 1'b1 : block_size;
            state <= STATUS;
          end else state <= WAIT_WRITE;
        end
        PROBE_START: begin
          request_sector <= 0;
          sector_write <= 0;
          sector_request <= 1;
          state <= PROBE_WAIT;
        end
        PROBE_WAIT:
        if (request_complete) begin
          if (request_error) begin
            examined[active_drive] <= 1;
            state <= IDLE;
          end else begin
            buffer_addr <= 0;
            state <= PROBE_GAP;
          end
        end
        PROBE_GAP: state <= PROBE_PARSE;
        PROBE_PARSE: begin
          case (buffer_addr)
            0:  rdb_signature[31:24] <= buffer_read;
            1:  rdb_signature[23:16] <= buffer_read;
            2:  rdb_signature[15:8] <= buffer_read;
            3:  rdb_signature[7:0] <= buffer_read;
            66: parsed_cylinders[15:8] <= buffer_read;
            67: parsed_cylinders[7:0] <= buffer_read;
            70: parsed_sectors[15:8] <= buffer_read;
            71: parsed_sectors[7:0] <= buffer_read;
            74: parsed_heads[15:8] <= buffer_read;
            75: parsed_heads[7:0] <= buffer_read;
          endcase
          buffer_addr <= buffer_addr + 1'b1;
          state <= buffer_addr == 75 ? PROBE_FINISH : PROBE_GAP;
        end
        PROBE_FINISH: begin
          if (!mount_event && !amiga_reset) begin
            if (probe_commit) present[active_drive] <= 1;
            examined[active_drive] <= 1;
            state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
      // Suppress stale FIFO/status strobes immediately; physical transactions drain under the arbiter.
      if (service_state && state != GET_REGS && !cancelled &&
          (image_mounted[{2'b10, active_drive}] || !mounted[active_drive]) &&
          state != ERROR_REG && state != ERROR_GAP && state != STATUS && state != STATUS_GAP) begin
        error_code <= 8'h04;
        status_value <= 8'hd1;
        after_status <= IDLE;
        sector_request <= 0;
        state <= ERROR_REG;
      end
      if (service_state && cancelled) begin
        state <= IDLE;
        sector_request <= 0;
      end
      if (image_mounted[{2'b10, active_drive}] && state >= PROBE_START && state <= PROBE_FINISH) begin
        state <= IDLE;
        sector_request <= 0;
      end
      if (amiga_reset) begin
        state <= IDLE;
        sector_request <= 0;
      end
      if (timer == TIMEOUT_CYCLES && state != IDLE) begin
        sector_request <= 0;
        if (service_state && !cancelled) begin
          error_code <= 8'h40;
          status_value <= 8'hd1;
          after_status <= IDLE;
          state <= ERROR_REG;
        end else begin
          examined[active_drive] <= 1;
          state <= IDLE;
        end
      end
      // Media invalidation has final priority, including probe completion/error/timeout.
      // Warm Amiga reset retains mounted geometry but clears SET MULTIPLE MODE state.
      for (drive = 0; drive < 2; drive = drive + 1) begin
        if (image_mounted[4+drive]) begin
          // Reject unaligned/oversized images before any narrowed capacity can be used.
          mounted[drive] <= image_size >= 512 && image_size <= 64'h2000000000 && image_size[8:0] == 0;
          examined[drive] <= 0;
          present[drive] <= 0;
          multiple[drive] <= 0;
        end
        if (amiga_reset) multiple[drive] <= 0;
      end
    end
  end
endmodule
// vim: ts=2 sw=2 tw=120 et
