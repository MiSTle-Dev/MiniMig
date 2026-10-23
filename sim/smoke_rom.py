#!/usr/bin/env python3
"""Generate an original 68000 smoke ROM; no copyrighted Kickstart is bundled."""
from pathlib import Path
import argparse
parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
parser.add_argument('--rtg-registers', action='store_true', help='check RTG enable write/readback before success')
args = parser.parse_args()
rom = bytearray([255]) * 524288
# Initial SP/PC; configure CIAA and disable ROM overlay, then write chip RAM and COLOR00.
code = bytes.fromhex('0001000000f8000813fc000300bfe20113fc000200bfe001')
if args.rtg_registers:
  # MOVE.W #1,$B80110; MOVE.W $B80110,D0; CMPI.W #1,D0; BNE.S *.
  # A failed register transaction cannot reach the chip-RAM success signature.
  code += bytes.fromhex('33fc000100b80110303900b801100c40000166fe')
code += bytes.fromhex('33fc12340001000033fc0f0000dff18060fe')
rom[:len(code)] = code
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(rom)
# vim: ts=2 sw=2 tw=120 et
