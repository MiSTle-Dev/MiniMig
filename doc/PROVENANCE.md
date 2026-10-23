# Source provenance

The baseline is the current local `icepi-zero-minimig` working tree, including its local modifications.
The original repositories are not modified. No other board targets or EightThirtyTwo sources are imported.

`source-provenance.json` records source paths and SHA-256 hashes of imported baseline files, before local adaptation.
Unmodified stable RTL is copied byte for byte; adapted stable files retain their existing indentation and author notices.
NanoMig-derived and newly authored text uses spaces with `ts=2 sw=2 tw=120 et`.

Imported NanoMig components are MCU SPI, system control, HID/keymap, native SD transport, sector RAM wrappers,
the sector-based Paula floppy backend, u8g2 rendering, and the simulator's SD/Companion models. The SDRAM simulation model derives from the user-selected
`snestang/src/verilator/sdr_chip_model.v`, extended for the stable controller's bursts.
`rtl/mistle/sdc_controller.sv` extracts and adapts the image/IDE service role embedded in NanoMig's `src/nanomig.v`:
media mount/RDB geometry, IDENTIFY, sector read/write scheduling, management/FIFO byte conversion and floppy/HDD sharing.
It uses the stable MiniMig HDD service interface, not NanoMig's incompatible management-register interface.
The stable `ide.v` gains a read-only command metadata output for cancellation checks; its FIFO and guest interface remain.

The new controller fixes per-drive geometry/initialization, exact-capacity bounds, transfer ownership and cancellation.
It adds no storage formats, CD-ROM handling or fallback CHS division. One shared synchronous sector RAM maps to an EBR.
The retained storage tests exercise the production FIFO and can be used for later resource or behavior changes.

The simulator fixes NanoMig's short-final-ROM-chunk handling: a partial `fread` at EOF must be transmitted rather than
silently discarded. Vendor FPGA memory netlists are not required by the Verilator simulator; behavioral wrappers are
isolated under `sim` and do not enter FPGA builds.

The stable project's GPL license is included as `LICENSE`. Existing copyright and license notices remain in source
files. The code also retains notices from the original MiniMig authors and the USB HID and HDMI implementations.

SPI flash support imports NanoMig's `flash_dspi.v` reader and preserves its dynamic `mspi_clk_ts`/USRMCLK interface.
A small startup sequencer adapts its 16-bit words to the stable 32-bit SDRAM host port and drains outstanding writes
before Companion takes ownership. The flash reader now runs on unshifted 28 MHz: command/address/control update
on falling edges and incoming data is captured on rising edges. A bundled toggle handshake retains every one-cycle
114 MHz request across the read, then returns the stable word to the unchanged SDRAM-domain boot sequencer.
The reader also resets its state and both request-edge registers explicitly.

The stable input-event regression is adapted for Companion's toggle interface. The virtual-top adapter converts each
held HID event into exactly one `clk7_en` mouse strobe; the CIA keyboard retains its independent toggle consumer.
