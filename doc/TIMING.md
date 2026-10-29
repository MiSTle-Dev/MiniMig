# Timing exceptions

Both board LPFs contain implementation exceptions; their SDC files carry the corresponding synthesis exceptions.
The inherited cache multicycles deliberately differ between SDC and LPF and remain unchanged.

## OSD and menu settings

The original IcePi LPF blocks paths into the RTG OSD enable synchronizer. Moving the renderer to the board top
requires the new `osd_rtg/enable_sync[0]` path in the LPF as well as SDC. Only the asynchronous first stage is exempt;
the path from the first stage to the second remains timed. `syn_preserve` retains these registers.

The configuration latch moved from `USERIO1/osd1` to `USERIO1/control`; filters and scanlines use that hierarchy.
Screen mode and offsets route directly from Companion to HDMI. Their held-setting exceptions use
`companion/control/system_video*` (including `system_video_screen`), `companion/control/system_xoffset*` and
`companion/control/system_yoffset*` in LPF, with the corresponding dotted hierarchy in SDC.
Companion system CPU/chipset/video/memory, turbo/overclock and volume settings follow NanoMig's existing
`sysctrl/system_*` exceptions, under the imported instance name `companion/control`.
These exceptions cover held settings, not bitmap address counters or live video.

SDC describes the two mutually exclusive generated pixel clocks and their asynchronous parents. Diamond LPF instead
has one DCSC output frequency at 66 MHz, the fastest supported pixel rate. Native OSD pixels can only reach HDMI
when the native 28 MHz parent is selected. As with the existing `virtual_top/DVI_*` exception, a 34.96 ns maximum
path delay preserves that native setup requirement. Both CELL and explicit EBR ASIC endpoints are covered. Do not globally false-path the OSD framebuffer: bitmap pixels
are real video data. The native renderer still has its original combinational pixel output and video latency.

## Disk DMA length to Agnus

NanoMig already uses a four-cycle exception from `PAULA1/pf1/dsklen*` to `AGNUS1/bl1/*`, with setup 4 / hold 3
in SDC and `4X` in LPF. That exception is retained here and extended narrowly to the sprite pointer RAMs.
SDC follows the preserved `sprpth_in`/`sprptl_in` nets because inferred RAM instances are renamed during mapping.
LPF targets the mapped distributed RAM write cells directly.
Both `dsklen` updates and sprite pointer writes are gated by the same `clk7_en`, active once per four 28 MHz cycles.
Other floppy-controller paths remain timed normally, including its 28 MHz sector buffer logic.

The reported path follows `dsklen -> lenzero -> disk DMA request -> Agnus arbitration -> shared RAM bus -> sprite
pointer data`. The DMA request equations and the sprite pointer arithmetic are also present in the stable IcePi
sources. Changing the host, floppy buffers and placement changes routing and can expose this path; a stable source
baseline does not imply identical post-route delay. The sprite pointer RAM is distributed RAM, not an EBR with a
missing optional output register. Adding buffering would alter the existing sprite DMA schedule and would not fix
the reported input path. No datapath register or RAM latency is changed for these exceptions.

## Stable TG68K budgets

All inherited TG68K multicycle lines are unchanged from the stable IcePi board files: 29 in SDC and 32 in LPF
for each board, excluding the removed host-controller buffer exceptions. This includes the differing cache budgets.
No new CPU/RTG-palette exception or relaxed RTG-acknowledgement budget is added. The final focused acknowledgement check passes at these existing budgets. Other CPU/cache violations remain
real implementation failures; they are not waived by this work.

The held Companion `osd/enabled` configuration bit is also exempt, consistent with the original menu settings.
LPF and SDC both exempt only the first stages of the ROM-loader, SPI-receive, OSD-reset and flash-takeover handshakes.

Run `python3 tools/audit_timing.py` to summarize both routed reports. With
`--baseline ../icepi-zero-minimig`, it also checks every inherited TG68K multicycle line against the original files.
A nonzero failing-entry count means timing is still open; generating a bitstream does not change that result.

## 28 MHz SPI flash

`USRMCLKI` is the existing `clk_28m` net, without an inversion or an extra generated clock. The SDRAM output clock
retains its existing 180-degree relationship. The flash reader's output/control logic uses falling edges;
its input shift register captures on rising edges. These are real half-cycle paths and remain timed.

`flash_dspi_reader` bridges system requests to the slower reader using held address/data and a toggle handshake.
Only the first `req_sync`, `ack_sync`, `ready_sync` and reset-release stages have false-path exceptions. Later
synchronizer stages remain timed. A 17 ns maximum delay on `held_data -> dout` preserves the return bus's two-system-
cycle settling requirement instead of inheriting the broader 28 MHz-to-system multicycle. SDC and LPF agree.
The boot sequencer and its sixteen-system-cycle SDRAM drain are unchanged. `mspi_clk_ts` stays a dynamic D12 input.
