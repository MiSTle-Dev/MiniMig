# Validation

Local validation on 2026-10-23, with Icarus Verilog, GHDL, Verilator and Lattice Diamond 3.14.

## Functional checks

| Check | Result |
| --- | --- |
| Production IDE/FIFO regression | Pass |
| Extracted storage controller with real IDE/FIFO | Pass: two drives, RDB/CHS/LBA bounds, multiple mode, byte order, arbitration, cancellation and errors |
| Companion SPI/configuration/OSD | Pass: all CPU selections, memory encodings, reset latches and turbo/overclock gating |
| Kickstart loader | Pass: complete 256/512 KiB uploads, mirroring, every host write, acknowledgement delays and retry |
| SDRAM model | Pass: CASDELAY=2 bank interleaving, pipelined/interrupted bursts and byte masks |
| Flash startup sequencer | Pass: addressing, paired data, host acknowledgements and takeover/drain |
| Pin-level 28 MHz DSPI | Pass: BBh/continuous reads, delayed pin data, clock-domain handshake, reset and abort/drain |
| Companion input adapter | Pass: 10,528 events, 2,120 keyboard deliveries, signed movement/wheel, all arrival phases, bursts and reset |
| RTG OSD | Pass: bitmap layout, scaling, enable, blank gaps and reset |
| Retained HDMI/RTG FIFO/register/vblank/audio/checksum and clock-switch benches | Pass |
| Optional local USB joystick elaboration | Pass with USB enabled; default remains disabled |

`make test` runs the IDE and MiSTle/input regressions. Physical SD signaling is exercised by the migrated simulator;
the storage unit bench uses a transactional sector transport. No copyrighted ROM or disk images are bundled.

## Production-core simulator

The generated smoke ROM uploads through the Companion image FIFO and production Kickstart loader into the real
SDRAM controller/model, disables the Amiga ROM overlay and executes on the production TG68K.
It writes `$1234` to chip RAM at `$10000`; completion is checked by the simulator, not inferred from an idle CPU.

Zero-profile 68000 and 68020 runs pass at approximately 97.620 ms. The XL-profile 68020 run also passes.
The default model uses the Zero profile. The SDRAM model defaults to CASDELAY=2, while the MiniMig instance uses
CASDELAY=3 to match the production controller's mode-register programming.

The additional RTG-register ROM writes `$B80110`, reads it back through the real CPU transaction interface and
checks the value before reaching the success signature. It passes with 68020. Reproduce with
`CPU=3 make -C sim smoke-rtg`. This does not establish physical RTG clock switching or timing closure.

## FPGA mapping

| Resource | Zero (25F) | Zero XL (45F) |
| --- | --- | --- |
| Registers | 8,825 | 8,800 |
| Slices | 12,143 / 12,144 | 14,056 / 21,924 |
| Total mapped LUT4s | 21,802 / 24,288 | 22,014 / 43,848 |
| Logic LUT4s | 17,536 | 17,744 |
| EBRs | 49 / 56 | 49 / 108 |

Total mapped LUT4s include carry and distributed-RAM resources, unlike the synthesis report's ORCALUT4 count.
The current storage service uses 864 ORCALUT4s on Zero, 854 on XL, and one sector-buffer EBR. The earlier large
sector-register bank and geometry division are removed. There is no fallback geometry or added storage format.

Both boards complete bitstream export. Full timing is still open: the final standard reports contain 20,323 setup /
25 hold errors on Zero and 16,905 setup / 116 hold errors on XL. These totals differ from the limited verbose path
list; the audit tool reports both. The remaining failures include CPU/cache paths and have not been waived.
No FPGA has been programmed by the build scripts.

The targeted new OSD enable, native OSD EBR, held menu settings and disk-length-to-Agnus preferences report zero
errors on both boards. A focused read-only TRACE check additionally groups CPU-to-`rtg_reg_ack_d` paths using the
same effective three-/four-cycle budgets already in the original LPF. It reports zero setup and hold errors for
both boards; project constraints and routed designs are not modified by that diagnostic.

The mapped preferences retain 28 inherited TG68K multicycle statements with their original values. Four original
source patterns (`Kernel_inst/addr[*]` and `Kernel_inst/long_cand*`, each to SDRAM and cache) are not emitted by the
mapper. They remain unchanged in the source files; no new CPU budget is introduced.

All original TG68K multicycle lines remain unchanged, including the deliberate SDC/LPF cache differences.
Use `python3 tools/audit_timing.py --baseline ../icepi-zero-minimig` to verify that comparison.
New OSD/Companion/floppy timing exceptions are described in [TIMING.md](TIMING.md).

## Hardware feedback and open work

The user's first board test confirms Amiga and IDE operation. Mouse movement was faulty because the new integration
held its strobe permanently high; the corrected toggle adapter passes the retained input regression and awaits
hardware retesting.

RTG did not switch from native video. CPU register write/readback works in simulation, but that does not exclude a
hardware timing fault. The existing TG68K timing budgets are preserved; the new framework's OSD/CDC constraints are
now covered, and the reported acknowledgement failure no longer appears in the focused timing check. RTG is not yet confirmed working on hardware.

The earlier 114 MHz SPI flash boot failed the first hardware test. The revised reader runs at unshifted 28 MHz,
launches on falling edges and samples on rising edges. It passes a pin-level DSPI model with 6 ns output delay,
verified startup/continuous-mode transactions, unrelated host/flash phases, reset and abort. This revision awaits
hardware retesting; simulation does not establish the board's electrical timing. Physical optional USB joysticks have not
been tested. Full ROM/OS boot, framebuffer display and audio/video electrical behavior need board testing.
