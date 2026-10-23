# Companion configuration

The menu and core decoder use the existing MiSTle byte-value setting protocol. Choice, toggle, file-selector and action
syntax are unchanged. `config/amiga.xml` is authoritative; `tools/build_menu.py` generates deterministic gzip/hex data and
a zero-padded 2048-byte ROM image. The menu has a dedicated EBR: `AMIGA_MENU_BYTES` is its full 2048-byte capacity,
with 11 address bits. The generator rejects compressed payloads exceeding that capacity. Save/reload still uses
`amiga.ini`.

| ID | Setting | Encoding |
| --- | --- | --- |
| T | CPU | 0=68000, 1=68010, 2=68EC020, 3=68020 |
| Z | Turbo | 0=off, 1=chip, 2=Kickstart, 3=both |
| O | Overclock | 0=off, 1=request on; effective only when Z=3 |
| C | Chipset | 0=OCS A500, 1=OCS A1000, 2=ECS, 3=AGA; AGA maps to stable encoding 6 |
| Y | Chip RAM | 0=512 KiB, 1=1 MiB, 2=1.5 MiB, 3=2 MiB |
| X | Slow RAM | 0=none, 1=512 KiB, 2=1 MiB, 3=1.5 MiB |
| Q | Fast RAM | 0=none, 1=2 MiB, 2=4 MiB, 3=Maximum |
| R | Reset | 1=hold, 0=run; ROM readiness also gates release |
| V | Video | 0=PAL, 1=NTSC |
| W | Screen | 0=standard, 1=overscan, 2=wide |
| F | Filter | 0=none, 1=horizontal, 2=vertical, 3=both |
| L | Scanlines | 0=off, 1=dim, 2=balanced |
| D | Floppy count | Number of additional drives, 0–3 |
| S / P | Floppy speed / protection | 0=normal, 1=fast / 0=writable, 1=protected |
| I | IDE | 0=disabled, 1=enabled; primary master and slave only |
| J | Joystick swap | 0=off, 1=on |
| A / M | Audio volume / mono mix | Volume 0–4 represents mute through 100%; mix 0=off, 1=on |
| f | Paula audio filter | 0=auto, 1=off, 2=on |
| a | Autofire | 0=off, 1=fast, 2=medium, 3=slow |
| H / N | Video offsets | Existing byte-value setting protocol; defaults 166 / 47 |

CPU type, chipset and RAM configuration latch during Amiga reset; turbo/overclock remain live controls.
Cold defaults match the stable IcePi profile: CPU 68000, OCS, 1 MiB chip, 512 KiB slow, 2 MiB fast, turbo off,
overclock off and IDE disabled. Unsupported NanoMig data-cache controls are omitted.

An existing NanoMig `amiga.ini` may contain CPU value 2 meaning 68020; here 2 explicitly means 68EC020.
Re-select and save the CPU mode after migration. Fast RAM value 3 means the stable core's `Maximum`, not a fixed 8 MiB.
Its actual allocation depends on CPU mode and the existing autoconfiguration logic, which is retained.

OSD commands go directly from Companion into the framework bitmap decoder/renderers. Bitmap writes and pixels do not
pass through `minimig.v`, `userio.v` or a legacy MiniMig SPI interface. Userio receives visibility only for guest input
suppression, plus the direct configuration signals. Native video uses the adapted NanoMig u8g2 renderer; RTG uses a
separate framebuffer reader in its pixel domain.

The startup flash copy remains available when Companion has no ROM image to upload. Like NanoMig, choosing an empty
ROM selection after an upload keeps the currently loaded ROM; reloading the FPGA restores the flash startup source.
