.PHONY: test menu zero xl sim smoke

test:
	python3 bench/mistle/run.py
	$(MAKE) -C bench/ide test
	$(MAKE) -C bench/input test

menu:
	python3 tools/build_menu.py

zero:
	./fpga/icepi-zero/build.sh

xl:
	./fpga/icepi-zero-xl/build.sh

sim:
	$(MAKE) -C sim all

smoke:
	$(MAKE) -C sim smoke
