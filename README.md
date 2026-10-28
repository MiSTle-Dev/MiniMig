# MiniMig MiSTle for IcePi Zero and IcePi Zero XL

A standalone merge of the current `icepi-zero-minimig` Amiga core with NanoMig's MiSTle FPGA Companion framework.
Only IcePi Zero (LFE5U-25F) and IcePi Zero XL (LFE5U-45F) are included.

The stable TG68K, chipset, Amber, SDRAM/cache, RTG, C2P and HDMI/audio paths are retained. The board top is SystemVerilog.
EightThirtyTwo, cfide, controller firmware, VGA/dithering, jcapture/JTAG debug, I2S and drive-sound outputs are removed.
Extra audio and other features disabled in the original IcePi top remain disabled. Local USB is optional and joystick-only.

## Build

Install Lattice Diamond 3.14, `diamondc`, `grc`, and Python 3. No firmware or submodule initialization is needed.

```sh
make zero
make xl
```

Each build generates its compressed Companion menu from `config/amiga.xml`, then builds its own board project.
Builds do not program the board. Bitstreams, resource reports and timing reports are in each board's
`Minimig_IcePi-Zero*` implementation directory. A generated bitstream alone does not establish timing closure.

## FPGA Companion and media

### Companion setup and wiring

Both boards use NanoMig's [IcePi Carrier](https://github.com/MiSTle-Dev/Boards/tree/main/icepi_carrier) interface.
Use a carrier with its support MCU, or wire a supported standalone Companion such as a Raspberry Pi Pico/RP2040.
Install [FPGA Companion firmware](https://github.com/MiSTle-Dev/FPGA-Companion) built for the actual MCU/carrier;
see its [RP2040 setup guide](https://github.com/MiSTle-Dev/FPGA-Companion/tree/main/src/rp2040) for firmware and pinouts.
For a Pico, hold BOOTSEL while connecting USB and copy the matching `fpga_companion.uf2` onto the bootloader drive.
Program the FPGA separately with the bitstream for **Zero or Zero XL**, respectively.

Connect the USB keyboard, mouse and USB joysticks to Companion's USB host interface. Companion manages the OSD,
configuration and filesystem sector translation; the FPGA performs the native SD transfers and Amiga image/IDE work.
The MCU and its connection must work for SD-backed images to be usable, even when Kickstart boots from SPI flash.

GPIO17 selects the SPI wiring: leave it unconnected (internal pull-down) or drive it low for standard wiring;
drive it high at 3.3 V for alternate wiring. Set the selector before SPI communication starts and keep it fixed
during operation. The mappings below apply to both Zero and Zero XL; parentheses give physical header pin numbers.
Alternate wiring follows the standard Raspberry Pi GPIO header SPI0 pinout: CE0 on GPIO8, SCLK on GPIO11,
MOSI on GPIO10 and MISO on GPIO9.

| Signal | Standard wiring | Alternate wiring | Direction relative to FPGA |
| --- | --- | --- | --- |
| SPI chip select, active low | GPIO18 (12) | GPIO8 (24) | Input |
| SPI clock (SCK) | GPIO24 (18) | GPIO11 (23) | Input |
| Companion-to-FPGA data (MOSI) | GPIO25 (22) | GPIO10 (19) | Input |
| FPGA-to-Companion data (MISO) | GPIO21 (40) | GPIO9 (21) | Output |
| Companion interrupt, active low | GPIO22 (15) | GPIO22 (15) | Output |
| Wiring selector | GPIO17 (11): low | GPIO17 (11): high | Input |

The unused MISO pin is high impedance: GPIO9 in standard mode, GPIO21 in alternate mode.

SPI uses MODE1. For a hand-wired setup, NanoMig's IcePi guide specifies a **220-ohm series resistor on SCK**.
Use the carrier schematic or Companion pinout for the MCU end of each connection and connect a common ground.
Standard wiring retains both physical joystick ports on GPIO0–11. Alternate wiring reuses GPIO8–11 for SPI and
disables those physical inputs on the second joystick port; GPIO6 and GPIO7 remain available, and Companion joystick
input still works. The first physical joystick port on GPIO0–5 is unchanged.
The native four-bit SD interface is CMD=N16, CLK=P15,
DAT0=P14, DAT1=R14, DAT2=M15 and DAT3=M14. Both FPGA variants use this interface.

### SD card, images and OSD

Prepare a FAT32 SD card with your Amiga media. The embedded menu uses these defaults; files can also be selected
through the OSD:

| Media | Slot | Default filename |
| --- | --- | --- |
| Floppy DF0–DF3 | 0–3 | `df0.adf`–`df3.adf` |
| Hard disk DH0–DH1 | 4–5 | `dh0.hdf`, `dh1.hdf` |
| Kickstart upload | ROM image 0 | `kick.rom` |

Start with `df0.adf` and a Kickstart image. Open the Companion menu with its default **F12** hotkey;
**Shift+F12** opens the Companion system menu and **Esc** goes back/closes the menu.
The hotkey can be changed in Companion firmware configuration. Save/reload uses `amiga.ini`.
The FPGA supplies the menu from `config/amiga.xml`, using the existing Companion XML control types.
Its compressed payload has a dedicated 2048-byte EBR; changes are generated with `make menu` and included in FPGA builds.

Enable **Storage → IDE** to use HDFs. Images must contain an **RDB at byte offset 0**, with no leading unallocated
space; geometry is read from that RDB. This matches NanoMig's whole-disk HDF approach. CD-ROM, raw-card/partition
mounting and synthetic RDB creation are unsupported. HDF files must have a sector-aligned size within LBA28 addressing.

### Kickstart and core settings

Select a 256 KiB or 512 KiB Kickstart ROM through Companion. A 256 KiB ROM is mirrored in the 512 KiB SDRAM window.
At power-on the NanoMig DSPI reader can instead copy a 512 KiB ROM from flash byte offset `0x400000`.
For a 256 KiB ROM, program the same file at `0x400000` and `0x440000`, as in NanoMig.
`USRMCLK` uses the unshifted 28 MHz clock. The DSPI reader launches command/address data and chip select on
falling edges and samples returned data on rising edges. Its `mspi_clk_ts` input remains on D12 with a pull-down
(0 drives the clock). A request/acknowledge bridge connects the reader to the 114 MHz SDRAM boot sequencer. Companion ROM upload overrides the startup flash copy.
The Amiga stays reset until the selected ROM copy is acknowledged by SDRAM.
Companion and its OSD remain available while the Amiga is reset.
The earlier 114 MHz flash implementation failed the first hardware test. The 28 MHz revision passes pin-level
simulation and has been confirmed working on hardware.

CPU choices are 68000, 68010, 68EC020 and 68020. Turbo chip/Kickstart settings and overclock remain separate;
overclock is effective only with both turbo settings enabled. Fast RAM retains the stable core's `Maximum`
autoconfiguration behavior. See [configuration mappings](doc/CONFIGURATION.md).

For optional local USB joysticks, set board-top parameter `USB_JOYSTICKS=1` and rebuild.
Keyboard and mouse support are disabled in those hosts; Companion handles keyboard/mouse input.
Joystick input sources merge before the swap setting is applied.

## RTG video (Picasso96)

Both IcePi Zero and Zero XL retain the IcePi MiniMig RTG implementation. RTG stores its framebuffer in Fast RAM
and outputs a fixed **1024×768 HDMI raster at a 66 MHz pixel clock**. Native Amiga video is selected at boot;
Picasso96 switches to RTG when an RTG screen is opened. Companion continues to provide the OSD in either mode.

Select a **68020 CPU configuration** and enough Fast RAM for AmigaOS and the framebuffer. Use the matching
`minimig.card` **1.15** driver included in this repository. It reserves 4 MiB by default and reduces the reservation
if allocation fails. The monitor tooltype `VIDEOMEMORY=<n>` requests 1–7 MiB.

### Build the RTG driver

Run from the repository root:

```sh
make -C amiga_sw/rtg
```

Requirements are GNU make 4.3+, bash, curl, 7z, Python 3, `xdftool` from amitools, and an installed
`vasmm68k_mot` assembler (default `~/vbcc/bin/vasmm68k_mot`). Set `VBCC=/path/to/vbcc` for another installation.
Missing Amiga NDK and P96 headers are downloaded into `amiga_sw/rtg/.deps` and reused; the assembler is not downloaded.

The build produces `minimig.card`, its assembler listing, the read-only `rtgcheck` diagnostic, and
`minimig-rtg.adf`, an 880 KiB OFS transfer disk named `MinimigRTG`. It also builds a separate 720p driver and ADF,
but **use the regular 1024×768 files for these board builds**. A 720p driver alone cannot change the FPGA raster;
720p gateware is not supplied here. Serial logging is disabled by default; `DEBUG=1` enables it.

### Install and select an RTG screen

1. Install Picasso96 on the Amiga; P96 2.0 is supported. If a board choice is required, select **PicassoIV** to
   obtain a monitor executable.
2. Mount `amiga_sw/rtg/minimig-rtg.adf` and copy the driver from an Amiga Shell:

   ```text
   Copy MinimigRTG:Libs/Picasso96/minimig.card LIBS:Picasso96/minimig.card
   ```

3. Rename `DEVS:Monitors/PicassoIV` and `PicassoIV.info` to `Minimig` and `Minimig.info`.
4. Open the Minimig monitor icon's Information window, set `BOARDTYPE=minimig`, and optionally add
   `VIDEOMEMORY=<n>`.
5. Reboot, open **Picasso96Mode**, attach a setting to the Minimig board, create and test modes, then save.
   Select a tested Workbench mode in **Prefs:ScreenMode**.

The driver does not install a mode list automatically. The ADF transfers the driver; install Picasso96 separately.
Run `MinimigRTG:rtgcheck` to inspect board ID/status, available Fast RAM and driver detection without switching video.

### Modes and limitations

The driver chooses the largest independent horizontal and vertical pixel repetition factors that fit the raster,
with black borders around the viewport. CLUT (8-bit), RGB565 and RGB555 formats are supported.

| Repetition factor | Maximum aligned source width | Maximum aligned source height |
| --- | --- | --- |
| 1× | 1024 | 768 |
| 2× | 512 | 384 |
| 3× | 336 | 256 |

Horizontal and vertical factors are independent: for example, 1024×384 uses 1×2 repetition, while 320×240 uses 3×3.
Smaller modes down to **320×192** are supported. Horizontal 4× cannot fit that minimum width in the supplied raster.
Visible dimensions and viewport boundaries use 16-pixel units. Nonaligned modes are cropped down while preserving
bitmap stride; borders are centered to that alignment, with unmatched space on the right/bottom.

Horizontal panning is unsupported. Dragged screens must share pixel format and repetition settings; split positions
retain single-output-line precision. Rendering uses the CPU, with no hardware blitter or sprite acceleration.
Applications control double buffering through P96. Vertical repetition rereads rows from SDRAM.

The core and driver must match: driver 1.15 programs explicit stride and viewport registers, and older drivers are
incompatible with this interface. Mode clock settings do not reprogram the physical HDMI timing.
See the [driver README](amiga_sw/rtg/README) for detailed behavior and version history.

## Tests and simulation

```sh
make test
make smoke
make -C sim run ROM=/path/to/kick.rom ARGS="--df0 /path/to/workbench.adf --seconds 10 --window"
```

`make test` requires Icarus Verilog and runs the retained production IDE regression plus the new storage,
configuration/SPI/OSD, Kickstart, SDRAM-model, flash-sequencer, pin-level DSPI and mouse/keyboard input tests.
The testbench files remain under `bench/mistle` for future regressions.

The simulator requires GHDL, Verilator, a C++ compiler and SDL2 development files. It migrates NanoMig's native SD and
Companion image model to the real stable TG68K, chipset and SDRAM path. It supports headless execution, an optional
window, FST traces and PPM screenshots. Disk images are read-only by default. See [simulation](sim/README.md).

The inherited focused CPU/cache and RTG/HDMI benches are retained. Some historical integration benches reference the
removed host/VHDL top and need adaptation before use. Physical USB, Companion wiring and FPGA timing require hardware
validation; simulation does not model FPGA routing or HDMI electrical signaling.

See [source provenance](doc/PROVENANCE.md) and [validation results](doc/VALIDATION.md).

## Credits

Dennis van Weeren created the original MiniMig.

The IcePi MiniMig project credits its code to the respective authors, copyright © 2005–2026.
Existing copyright and license notices are preserved in the source files. See [LICENSE](LICENSE) and
[source provenance](doc/PROVENANCE.md) for licensing and component origins.
