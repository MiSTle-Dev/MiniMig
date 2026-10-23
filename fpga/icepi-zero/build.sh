#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
python3 ../../tools/build_menu.py --output .
cp ../../rtl/usb_hid_host/rom/usb_hid_host_rom.mem .
grc --config=diamondc.grc diamondc build.tcl "$@"
