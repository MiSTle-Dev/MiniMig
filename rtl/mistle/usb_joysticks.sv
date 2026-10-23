// Optional local USB hosts. Keyboard/mouse decoding is excluded at elaboration.
module usb_joysticks #(
    parameter ENABLE = 0
) (
    input clk_usb,
    input clk,
    input reset,
    inout [1:0] usb_dp,
    inout [1:0] usb_dn,
    output [11:0] joy0,
    output [11:0] joy1,
    output [1:0] connected
);
  generate
    if (ENABLE) begin : enabled
      wire [9:0] rom_addr[0:1];
      wire [3:0] rom_data[0:1];
      wire [1:0] dp, dn, oe, rom_en;
      reg [11:0] state[0:1];
      reg [11:0] sync1[0:1];
      reg [11:0] sync2[0:1];
      wire [1:0] typ[0:1];
      wire [11:0] game[0:1];
      wire [1:0] report_done;
      (* ASYNC_REG = "TRUE" *) reg [1:0] reset_usb = 2'b11;
      always @(posedge clk_usb or posedge reset)
        if (reset) reset_usb <= 2'b11;
        else reset_usb <= {reset_usb[0], 1'b0};
      usb_hid_host_dual_rom #(
          .MEMORY_FILE("../../usb_hid_host/rom/usb_hid_host_rom.mem")
      ) rom (
          .clk  (clk_usb),
          .addra(rom_addr[0]),
          .douta(rom_data[0]),
          .ena  (rom_en[0]),
          .addrb(rom_addr[1]),
          .doutb(rom_data[1]),
          .enb  (rom_en[1])
      );
      for (genvar i = 0; i < 2; i = i + 1) begin : port_host
        assign usb_dp[i] = oe[i] ? dp[i] : 1'bz;
        assign usb_dn[i] = oe[i] ? dn[i] : 1'bz;
        usb_hid_host #(
            .KEYBOARD_SUPPORT(0),
            .MOUSE_SUPPORT(0),
            .GAME_SUPPORT(1)
        ) host (
            .clk(clk_usb),
            .reset(reset_usb[1]),
            .cs(1'b1),
            .usb_dp_i(usb_dp[i]),
            .usb_dm_i(usb_dn[i]),
            .usb_dp_o(dp[i]),
            .usb_dm_o(dn[i]),
            .usb_oe(oe[i]),
            .typ(typ[i]),
            .full_report(report_done[i]),
            .game_r(game[i][0]),
            .game_l(game[i][1]),
            .game_d(game[i][2]),
            .game_u(game[i][3]),
            .game_a(game[i][4]),
            .game_b(game[i][5]),
            .game_x(game[i][6]),
            .game_y(game[i][7]),
            .game_sel(game[i][8]),
            .game_sta(game[i][9]),
            .game_extra(),
            .rom_addr(rom_addr[i]),
            .rom_dout(rom_data[i]),
            .rom_en(rom_en[i])
        );
        // Complete reports are held through the CDC; no partial decoder updates reach the core.
        always @(posedge clk_usb) begin
          if (reset_usb[1] || typ[i] != 3) state[i] <= 12'hfff;
          else if (report_done[i]) state[i] <= {2'b11, ~game[i][9:0]};
        end
        always @(posedge clk) begin
          if (reset) begin
            sync1[i] <= 12'hfff;
            sync2[i] <= 12'hfff;
          end else begin
            sync1[i] <= state[i];
            sync2[i] <= sync1[i];
          end
        end
        assign connected[i] = sync2[i] != 12'hfff;
      end
      assign joy0 = sync2[0];
      assign joy1 = sync2[1];
    end else begin : disabled
      assign usb_dp = 2'bzz;
      assign usb_dn = 2'bzz;
      assign joy0 = 12'hfff;
      assign joy1 = 12'hfff;
      assign connected = 2'b0;
    end
  endgenerate
endmodule
// vim: ts=2 sw=2 tw=120 et
