# MiSTle integration regressions

Run `python3 bench/mistle/run.py` from the project root. Individual cases can be selected:

```sh
python3 bench/mistle/run.py storage
python3 bench/mistle/run.py control kickstart
```

- `storage_tb.sv` connects the extracted/adapted sector controller to the production stable IDE and FIFO RTL. It checks
  both RDB geometries, exact image capacity, last-sector access and bounds rejection, CHS increment on the second drive,
  multiple-mode configuration/read/write, payload byte order, floppy/HDD ownership, media replacement/ejection,
  command-generation cancellation, reset recovery, zero-count 256-sector reads, and native write errors.
- `control_tb.sv` sends real MODE1 Companion SPI transactions and checks CPU/RAM encodings, reset latching, overclock
  gating, chipset settings, u8g2 tile writes and OSD guest-input suppression.
- `kickstart_tb.sv` transfers complete 256/512 KiB streams across unrelated clocks, checks every SDRAM host write and
  address, 256 KiB mirroring, delayed acknowledgements, invalid selection and interrupted-upload timeout/retry.

- `sdram_tb.sv` checks CASDELAY=2 bank interleaving, sequential bursts, interruption, pipelined reads and byte masks.
- `flash_tb.sv` checks flash word addressing, paired 16-bit data, SDRAM host acknowledgements and Companion takeover.
- `flash_dspi_tb.sv` connects that sequencer to the real DSPI reader/clock bridge and a pin-level flash model.
  It checks BBh command/address/mode cycles, continuous reads, data delayed after falling edges, payload byte order,
  two host clock rates/phases, reset in continuous mode and during a read, plus abort during SPI and host writes.

The SD transport in the storage bench is a byte-accurate transactional model. Native SD command/data/CRC behavior and
Companion ROM FIFO integration are exercised by the migrated simulator instead. Physical timing remains a board check.
All temporary test products are created outside the source tree.
