#!/usr/bin/env python3
"""Generate Companion gzip XML in one dedicated 2 KiB byte-wide EBR."""
import argparse
import gzip
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
# One ECP5 DP16KD holds 2048 byte entries (the ninth bit per entry is unused).
MENU_BYTES = 2048
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=ROOT / "config")
args = parser.parse_args()
root = ET.parse(ROOT / "config/amiga.xml").getroot()
for node in root.iter():
  if node.text is not None and not node.text.strip(): node.text = None
  node.tail = None
payload = gzip.compress(ET.tostring(root, encoding="utf-8"), mtime=0)
if len(payload) > MENU_BYTES:
  parser.error(f"compressed menu is {len(payload)} bytes; one EBR holds at most {MENU_BYTES}")
rom = payload.ljust(MENU_BYTES, b"\0")
args.output.mkdir(parents=True, exist_ok=True)
(args.output / "amiga_xml.hex").write_text("".join(f"{b:02x}\n" for b in rom))
(args.output / "amiga_menu_size.vh").write_text(
  f"localparam integer AMIGA_MENU_BYTES = {MENU_BYTES};\n"
  f"localparam integer AMIGA_MENU_ADDR_BITS = {(MENU_BYTES-1).bit_length()};\n")
print(f"Companion menu: {len(payload)}/{MENU_BYTES} bytes in one EBR")
# vim: ts=2 sw=2 tw=120 et
