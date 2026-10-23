# Resource review: MiSTle/NanoMig integration

This is a source/report review, with no RTL changes and no new synthesis or FPGA builds.
The stable IcePi CPU, chipset, cache/SDRAM, Amber, HDMI and FIFO implementations are outside the optimization scope.
Candidate changes below apply to the imported/new integration modules. EBRs should remain separate, as requested.

## Evidence and baseline

The existing Zero area report is dated 2026-10-23 11:51; the XL report is dated 10:36. They predate the latest
menu/audio-filter/autofire edits and are snapshots, not measurements of prospective optimizations.
The Zero map report contains 17,610 logic LUT4s, 21,864 total mapped LUT4s, 8,820 registers, and 49/56 EBRs.
Slices are effectively full. Register utilization is only about 35%, so freeing registers alone is insufficient:
LUTRAM must also reduce logic or improve slice packing to be worthwhile.

`resource-review-snapshot.json` records the relevant hierarchical area figures. Counts include child instances;
for example, do not add SD command-controller counts to the parent SD stack a second time. ORCALUT4 figures exclude
separately reported carry logic, RAM and wide-mux resources; they are not the complete mapped-LUT footprint.

| Hierarchy, Zero snapshot | ORCALUT4 | Registers | CCU2C | EBR |
| --- | ---: | ---: | ---: | ---: |
| `companion.card` including SD command/data engine | 1,125 | 706 | 138 | 2 |
| `companion.card.sd_rw.u_sdcmd_ctrl`, included above | 416 | 130 | 41 | 0 |
| `virtual_top.storage` | 862 | 481 | 167 | 1 |
| Sector floppy backend, including stable FIFO | 471 | 294 | 83 | 3 |
| Stable FIFO inside that backend, excluded from changes | 331 | 69 | 22 | 2 |
| Native OSD renderer | 106 | 45 | 36 | 1 |
| Companion Kickstart loader | 71 | 195 | 47 | 0 |
| Flash bridge/reader together | 59 | 97 | 6 | 0 |
| Flash boot sequencer | 38 | 113 | 36 | 0 |

## Existing memory inference to preserve

The user's `NanoMig/src/minimig-aga/paula_floppy_ebr.v` is directly relevant: it is the source of
`rtl/mistle/paula_floppy_sector.v`. Comparing it with NanoMig's ordinary `paula_floppy.v` shows the consolidation
of two even/odd byte arrays into `paula_floppy_dma_buf`, with byte enables and the corrected registered-read latency.
The migrated design retains that implementation. The sector buffer uses **one DP16KD**.

These memories already use dedicated RAM:

- IDE sector buffer: one EBR, reported as PDPW16KD.
- Companion MCU sector buffer: one DP16KD.
- Companion 512-byte ROM-upload FIFO: one EBR, reported as PDPW16KD.
- Floppy decoded-sector buffer: one DP16KD.
- Menu ROM: one DP16KD.
- Native and RTG OSD bitmaps: one DP16KD each.
- Direct-image offset table, `direct_start[8]`: eight DPR16X4C primitives.
- Floppy drive-track table, `dsktrack[4]`: two SPR16X4C primitives.

PDPW16KD also consumes an EBR; it is not a register bank. No overlooked multi-kilobit register array was found in
the imported/new modules. The existing stable floppy FIFO is left untouched.

## 1. Reducing LUT usage

### First: SD command serialization and clock counters

Sources: `rtl/mistle/sdcmd_ctrl.v`, `rtl/mistle/sd_rw.v`.

`request[cnt]` selects from a 48-bit command packet using a 16-bit counter, alongside range checks and CRC control.
A constant-tap transmit shift path can remove that wide indexed mux. The current argument/command storage already
contains most packet bits, so the design should shift/reuse storage rather than add a second full packet copy.
Keep the command identifier needed for response checking and preserve the seven CRC bits' exact transmit order.
This is a stronger logic target than allocating RAM for a tiny serial command.

The board fixes `CLK_DIV=2`, with slow divider 144 and terminal clock count 289. Its active clock counter only needs
nine bits, while the mapped implementation retains the 18-bit `clkcnt`. A parameterized bound covering all existing
three-bit divider settings needs ten bits. Preserve divider-change boundaries and initialization/first-edge behavior;
replacing the reset-time `18'h3ffff` sentinel requires a deliberate startup-state rewrite. The 16-bit precount must
still accommodate 64,000; do not shrink it to the command's 48-bit length.

In `sd_rw.v`, CRC transmission uses `data_crc[i][15-ridx[3:0]]` on four lanes. Shift the four CRC registers while
transmitting, using a constant output tap, once their accumulated values are no longer needed. This can remove four
indexed selectors. Preserve the final payload nibble's CRC update and first/last CRC output edges. Four parallel CRC
feedback states should remain registers unless a separately measured time-multiplexed design wins.

### Second: arithmetic widths and byte/word conversion in the new IDE service

Source: `rtl/mistle/sdc_controller.sv`.

Use sized arithmetic in expressions such as `remaining - 1 < block_size`; the unsized literal promotes an otherwise
nine-bit operation. Inspect the mapped carry cone before claiming a saving, since synthesis may already reduce it.
Keep the maximum 256-sector command count and partial final multiple blocks unchanged.

Bound the CHS calculation's intermediate widths explicitly. The current expression maps to four MULT18X18D and two
ALU54B primitives. Reducing DSP usage is not itself a LUT reduction: replacing those multipliers with shift/add logic
could increase LUT use. Keep CHS/RDB behavior and introduce no division or fallback geometry.

The IDE sector buffer's SD side is byte-wide and the stable FIFO side is word-wide. A mixed-width EBR interface,
following the existing floppy buffer pattern, could remove byte assembly/address-mux states and related registers
while keeping one EBR. Preserve byte order and the stable FIFO strobes/read latency. This needs a focused experiment;
the stable IDE/FIFO RTL should not change.

Lower-priority candidates include sharing coarse timeout ticks between the three 28 MHz controllers and removing
provably redundant address staging. Neither should be counted as a large saving without mapping. Timeout granularity,
retry addresses and media/command cancellation behavior must remain explicit.

## 2. Registers to distributed RAM: actual amounts and reset requirements

`resource-register-inventory.json` counts mapped FD instances by register family, rather than just declaration widths.

| Candidate | Mapped registers attributed to it | Main obstacle | Assessment |
| --- | ---: | --- | --- |
| IDE capacity + geometry, both drives | 120 | Reset/mount/probe writes and independent update sources | Best table conversion to trial |
| IDE multiple-mode values | 10 | Both drives reset simultaneously on Amiga reset | Keep these registers initially |
| IDE taskfile capture | 46 | Several bytes read concurrently during decode | Requires sequential decode or staging reuse |
| Floppy checksum family | 32, including inference helper registers | Clear-all operations plus read/modify/write and paired output reads | Small, conditional opportunity |
| Floppy track table | Already SPR16X4C | None | Preserve existing inference |
| Direct-image table | Already DPR16X4C | None | Preserve existing inference |

### Capacity/geometry: remove payload resets, keep validity

The 120 mapped bits consist of capacity 62, cylinders 32, heads 10 and sectors 16. An approximately 60-bit row per
drive can be stored in a two-entry distributed table, with one synchronous write and an independent asynchronous
read. Keep `multiple` outside that table initially so Amiga reset does not require clearing two RAM rows.

Reset existing validity/presence flags, not every payload bit. A row becomes usable only after its mount data and
successful RDB probe are committed. An invalid row must never affect IDENTIFY, bounds decisions or SD requests.
A validity bit alone does not solve inference: mount and probe updates must also be reduced to a single write port,
with defined priority when a new image arrives during a probe. Partial updates require controlled read/modify/write.

This potentially repacks about **120 payload registers**, less any new staging/validity registers. The two-entry depth
underuses a distributed RAM's physical capacity; the LUT/packing result may improve or worsen. Measure it rather than
assuming register removal means LUT savings.

Heads and sectors are already pruned to five/eight bits per drive by synthesis. Those upper declaration bits are
not additional savings. A sector-capacity count supporting a full LBA28 image requires **29 bits**, not 28. The
current mapped capacity has 31 bits per drive; explicit safe narrowing would remove at most four more registers
across both drives. Do not narrow unvalidated RDB fields before checking their upper bits.

#### Implemented capacity/geometry cleanup

`rtl/mistle/sdc_controller.sv` now uses a reset-free, two-entry, 58-bit distributed RAM table. Each row contains a
29-bit sector count, 16-bit cylinders, five-bit heads and eight-bit sectors. A single synchronous write port handles
mount initialization and successful RDB probe commits; the active drive has an asynchronous read. The existing
`sd_card` protocol supplies one-hot mount notifications with a shared size payload. A mount takes priority over a
probe; a simultaneous probe completion for the other drive waits for the write port. Remount invalidation also has
priority over probe completion, failure and timeout in the validity registers.

Cold reset clears validity without writing the RAM. Amiga reset retains mounted geometry and clears the separate
multiple-mode registers. Parsed RDB fields remain wide until validation, and a 29-bit count preserves the full LBA28
image boundary. No EBR or new staging registers were added. This replaces the previous roughly 120 mapped payload
registers with 116 logical RAM bits; actual FF/LUT savings and distributed RAM mapping remain unmeasured because FPGA
builds are paused.

The storage regression covers unknown RAM before mounting, retained RAM after cold reset, warm reset including the
probe-commit cycle, remount during transfer and commit, another drive mounting during commit, invalid RDB high bits,
invalid image sizes, maximum geometry, maximum LBA28 capacity and end-crossing rejection, alongside the existing IDE,
CHS, multiple-mode, write-payload, transport-arbitration and error tests.

### Taskfile: resetting is not the problem

The taskfile array is already unreset. It retains 46 mapped registers after the unused error byte and unused drive
bits are removed. Its simultaneous fixed-field reads prevent a simple one-read-port RAM replacement. Sequential
field decoding could permit a small distributed scratch RAM, but temporary staging can consume the saved registers.
Reusing the existing LBA/count/command registers during capture may be cheaper than introducing scratch RAM.

### Floppy checksum: lazy initialization, with banked reads

`fd_dma_csum` clears four entries together and then updates one addressed entry per SD byte. Replacing payload
clears with per-entry validity/first-write handling can remove a RAM-inference barrier. The first XOR must use a
logical zero, not uninitialized RAM contents.

The MFM output reads two checksum bytes together. A single byte-wide, single-read-port table cannot replace it
unchanged. Even/odd banks can provide those paired reads, with read addresses selected between accumulation and
checksum emission. Preserve the forced MFM clock bits. The netlist attributes 32 FFs to this family, including
helper registers, so the gross opportunity is modest and validity/banking logic may erase much of the benefit.
A sector-level MFM checksum/read/write regression is needed before changing it.

Do not remove resets from FSMs, request ownership, FIFO pointers, valid flags, synchronizers or reset-release logic.
Do not move CDC synchronizer stages into LUTRAM. Small simultaneous snapshot buses in the flash/Kickstart interfaces
are poor RAM candidates; their clocks, hold times and handshake roles matter more than their declaration sizes.

## 3. Separate additional EBRs

### Best candidate: keyboard translation ROM

`rtl/mistle/amiga_keymap.v` maps to **seven ROM128X1A** primitives, representing the 128x7 keyboard map. A dedicated
DP16KD can replace this distributed ROM and its selection resources. It is underfilled, but available EBR budget
makes that a reasonable LUT trade. The order of potential savings is tens of LUTs; an exact number requires mapping.

EBR reads are synchronous. Pipeline the keyboard event's valid/type/release information alongside the lookup, then
update the translated event and Ctrl/Amiga reset-combination tracking together. Do not use the previous keycode or
lose the final event when SPI chip select rises. Keep the EBR separate from menu and sector memories.

### Optional: IDENTIFY constant template ROM

The fixed portions of IDENTIFY can reside in a separate synchronous 256x16 EBR, with geometry, capacity and multiple-
mode words patched from live drive metadata. Prefetch before each FIFO write to preserve handshake correctness.
This targets a small part of the 862-LUT storage controller, not its arithmetic/control bulk. Its benefit is likely
smaller than the keyboard ROM and could be offset by patch/prefetch logic. Allocate it only if a scoped measurement
shows a useful LUT/packing reduction. Do not use an EBR just for a two-entry geometry table.

Keep the existing sector buffers separate. Their read/write ownership and port requirements differ; spare capacity
inside a physical block does not make their ports interchangeable.

## Suggested implementation order

1. Narrow the SD clock generator safely and replace command/CRC indexed output muxes with constant-tap shifting.
2. Move the keyboard map into its own EBR with an explicit event pipeline.
3. Trial the roughly 120-bit geometry table as reset-free payload plus validity, retaining multiple mode in registers.
4. Evaluate the checksum banks and taskfile capture only after checking their net register/LUT savings.
5. Consider a separate IDENTIFY ROM or mixed-width IDE buffer if the first changes do not provide enough headroom.

Existing storage tests cover CHS/LBA, exact bounds, multiple mode, byte order and cancellation. Add pin-level SD
command/CRC boundary tests for the serializer changes, and complete HID/reset-combination tests for keyboard ROM
latency. Reset-free RAM changes need cold reset, Amiga reset, eject/remount and mount-during-probe cases.
Any later build should compare logic LUTs, carry LUTs, RAM primitives, total slices and timing, with each experiment
isolated. Preserve the stable core and its timing constraints throughout.
