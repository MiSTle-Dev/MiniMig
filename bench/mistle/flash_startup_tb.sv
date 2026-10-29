`timescale 1ns/1ps
// Exercise the real board-to-virtual-top reset wiring. Unrelated peripherals may
// remain unbound; the SDRAM initialization flag and PLL clocks are modeled here.
module flash_startup_tb;
  reg clk = 0, flash_clk = 0;
  always #4.375 clk = !clk;
  always #17.5 flash_clk = !flash_clk;
  reg locked = 0, memory_ready = 0;
  minimig_icepizero_top dut ();

  initial begin
    force dut.clk_sys = clk;
    force dut.clk_28m = flash_clk;
    force dut.pll_locked = locked;
    force dut.virtual_top.reset_out = memory_ready;
    force dut.rom_override = 1'b0;

    repeat (8) @(negedge flash_clk);
    if (dut.companion_reset !== 1'b1 || dut.rom_memory_ready !== 1'b0 ||
        dut.flash_host_req !== 1'b0 || dut.flash_cs !== 1'b0)
      $fatal(1, "power-on reset or SDRAM-ready wiring failed");

    locked = 1;
    repeat (8) @(negedge flash_clk);
    if (dut.companion_reset !== 1'b0)
      $fatal(1, "Companion reset did not release after PLL lock");
    if (dut.flash_reader_ready !== 1'b0 || dut.flash_cs !== 1'b0)
      $fatal(1, "flash started before SDRAM initialization");

    memory_ready = 1;
    wait (dut.flash_cs === 1'b1);
    if (dut.rom_memory_ready !== 1'b1 || dut.flash_address !== 23'h200000)
      $fatal(1, "flash boot did not start at the ROM offset");
    wait (dut.flash_host_req === 1'b1);
    #1;
    if (dut.host_req !== 1'b1 || dut.host_addr !== 24'h1e0000 || dut.flash_quiescent !== 1'b0)
      $fatal(1, "flash ROM write did not reach the SDRAM host port");

    // Loss of SDRAM readiness must reinitialize the boot path.
    @(negedge clk);
    memory_ready = 0;
    repeat (8) @(negedge flash_clk);
    if (dut.flash_host_req !== 1'b0 || dut.flash_reader_ready !== 1'b0)
      $fatal(1, "flash boot did not reset with SDRAM");
    memory_ready = 1;
    wait (dut.flash_host_req === 1'b1);
    #1;
    if (dut.host_addr !== 24'h1e0000) $fatal(1, "flash boot restart used a stale address");
    $display("PASS flash startup: board reset wiring, SDRAM readiness, ROM host request and restart");
    $finish;
  end
  initial begin
    #20000;
    $fatal(1, "flash startup timed out");
  end
endmodule
