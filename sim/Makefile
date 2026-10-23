PYTHON ?= python3
JOBS ?= 4
BOARD ?= icepi-zero
ROM ?=
ARGS ?=

.PHONY: all run smoke smoke-rtg
all:
	$(PYTHON) build.py -j $(JOBS) --board $(BOARD)

run: all
	./build/minimig-sim --rom "$(ROM)" $(ARGS)

smoke: all
	$(PYTHON) smoke_rom.py build/smoke.rom
	./build/minimig-sim --rom build/smoke.rom --smoke --seconds 0.2

smoke-rtg: all
	$(PYTHON) smoke_rom.py build/smoke-rtg.rom --rtg-registers
	./build/minimig-sim --rom build/smoke-rtg.rom --smoke --seconds 0.2
