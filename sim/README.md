# MiniMig MiSTle simulation

This migrates NanoMig's SD-card electrical model, Companion image-transfer model and mixed-width video RAM models.
The SDRAM model derives from `snestang/src/verilator/sdr_chip_model.v`, with bank interleaving and MiniMig's sequential read-burst support. Its default CASDELAY=2 matches the reference;
the MiniMig instance uses CASDELAY=3 to match the production controller's mode register.
The CPU/chipset/cache/SDRAM are the production stable MiniMig implementation. GHDL translates the current VHDL TG68K
and audio components at build time; no pre-generated CPU snapshot is shipped.

Requirements: Python 3, GHDL, Verilator, a C++ compiler, make, and SDL2 development files (`sdl2-config`).

```sh
make -C sim smoke
make -C sim run ROM=/path/to/kick.rom ARGS="--seconds 10 --df0 /path/to/workbench.adf --window"
```

The original smoke ROM is generated locally. It uploads through the Companion image FIFO and production Kickstart
loader into SDRAM, then executes on TG68K and writes `$1234` into chip RAM at `$10000`. The test fails if the signature
is not reached within its simulated-time limit. Neither Kickstart nor disk images are bundled.

`make -C sim smoke-rtg` additionally writes and reads back `$B80110` through the real CPU interface before
allowing the success signature. It checks RTG register transactions, not HDMI clock switching or physical timing.

Options for `sim/build/minimig-sim`:

- `--rom FILE`: required 256/512 KiB ROM; uploaded through the simulated Companion.
- `--df0 FILE` through `--df3 FILE`: ADF images.
- `--dh0 FILE`, `--dh1 FILE`: RDB-based HDF images.
- `--seconds N`: simulated runtime, default 0.2 seconds; real Kickstart boot needs a longer run.
- `--window`: SDL video display, keyboard and mouse events; close the window to stop.
- `--trace FILE.fst`: capture internal signal traces.
- `--screenshot FILE.ppm`: save the final native video frame.

Environment variables `CPU`, `CHIPSET` and `MEMORY` accept the stable core's numeric configuration bitfields.
Default CPU is 68000, chipset OCS, memory `$15`. Disk-image changes are not written back.

The wrapper retains NanoMig's direct Companion byte interface for the SD model; it does not simulate an RP2040 CPU.
Real Companion SPI dispatch is covered separately by `bench/mistle/control_tb.sv`.
The simulator models native Amiga video, not HDMI serializers or FPGA PLL analog behavior. The clock model supplies
the stable 4:1 SDRAM/native ratio; production clock-enable generation is retained. Behavioral EBR wrappers replace
vendor primitives with the same port widths, byte lanes and read latency. They do not model physical timing.

Simulation products and compiler caches stay under `sim/build`. Native execution can be much slower than real time.

Use `BOARD=icepi-zero-xl` with the Makefile to translate the XL CPU datapath/cycle profile instead of Zero.
