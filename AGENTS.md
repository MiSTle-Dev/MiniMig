# Repository Guidelines

## Project Structure & Module Organization

This merges IcePi MiniMig with NanoMig/MiSTle FPGA Companion support for IcePi Zero and IcePi Zero XL only.

- `rtl/minimig/`: retained Amiga chipset and IDE logic; other `rtl/` directories contain CPU, memory, and video modules.
- `rtl/mistle/`: Companion configuration, OSD, storage, and flash integration.
- `rtl/soc/`: board and virtual top modules.
- `fpga/icepi-zero/` and `fpga/icepi-zero-xl/`: board projects, LPF pin/timing constraints, and SDC constraints.
- `config/`: authoritative `amiga.xml` and generated menu ROM data.
- `bench/`: RTL regressions; `sim/`: full-system simulator.
- `tools/`, `doc/`, and `amiga_sw/`: generators, architecture/validation notes, and Amiga software.

## Build, Test, and Development Commands

- `make test`: Icarus Verilog regressions for storage, configuration, input, ROM loading, and SDRAM.
- `python3 bench/mistle/run.py storage control`: focused integration tests.
- `make menu`: regenerate the compressed, zero-padded 2048-byte menu ROM.
- `make sim`: build the GHDL/Verilator simulator; requires a C++ compiler and SDL2.
- `make smoke`: boot a generated test ROM in simulation.
- `make zero` / `make xl`: build FPGA images using Lattice Diamond, `diamondc`, and `grc`; these do not program hardware.

FPGA builds are currently paused at the maintainer's request. Run simulations and regressions; resume FPGA builds only
when requested.

## Coding Style & Naming Conventions

Use two-space indentation, spaces instead of tabs, and a 120-column limit for new and NanoMig-derived files
(`ts=2 sw=2 tw=120 et`). Preserve formatting in retained IcePi sources. Prefer descriptive snake_case module and signal
names. Keep generated menu files synchronized through `tools/build_menu.py`. Check patches with `git diff --check`.

## Testing Guidelines

Place focused SystemVerilog benches under `bench/mistle/` as `<feature>_tb.sv`; register new benches in `run.py`.
Cover reset, cancellation, media replacement, and boundary conditions when changing storage or configuration.
No numeric coverage threshold is established. Simulation passes do not establish FPGA timing closure or resource savings.

## Commit & Pull Request Guidelines

History contains one initial import; no commit convention is established. Use concise, imperative
subjects describing the affected behavior. PRs should explain the problem, changes, tests, and remaining hardware or
timing validation. Link relevant issues and include resource/timing comparisons when measured.

## Architecture Constraints

Treat retained IcePi chipset, CPU, SDRAM/cache, and Amber logic as the stable baseline. Preserve existing TG68K timing
budgets and intentional LPF/SDC differences. Keep EBR memories separate. Remove RAM payload resets only while retaining
validity and control resets. Use existing Companion protocols and XML capabilities; do not modify sibling source projects.
