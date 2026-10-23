#!/usr/bin/env python3
"""Build the migrated NanoMig environment against current production MiniMig sources."""
from pathlib import Path
import argparse
import os
import re
import shlex
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SIM = ROOT / 'sim'
BUILD = SIM / 'build'
parser = argparse.ArgumentParser()
parser.add_argument('-j', type=int, default=4)
parser.add_argument('--board', choices=('icepi-zero', 'icepi-zero-xl'), default='icepi-zero')
args = parser.parse_args()
BUILD.mkdir(exist_ok=True)
os.environ.setdefault("CCACHE_DIR", str(BUILD / ".ccache"))

def run(*command, **kwargs):
  subprocess.run([str(x) for x in command], cwd=ROOT, check=True, **kwargs)

sources = [f'fpga/{args.board}/board_config.vhd', 'rtl/tg68k/TG68K_Pack.vhd', 'rtl/tg68k/TG68K_ALU.vhd',
     'rtl/tg68k/TG68KdotC_Kernel.vhd', 'rtl/soc/TG68K.vhd', 'rtl/audio/audiofilter.vhd', 'rtl/audio/AudioMix.vhd']
run('ghdl', '-a', '--std=08', '-fsynopsys', f'--workdir={BUILD}', *sources)
for entity in ('TG68K', 'audiofilter', 'AudioMix'):
  options = ['-ghavertg=1', '-ghavec2p=1', '-ghavecart=0', '-ghaveaudio=0', '-ghaveamigahost=0',
       '-gsdram64meg=0', '-gusethrottle=0'] if entity == 'TG68K' else []
  with (BUILD / f'{entity}.v').open('w') as output:
    run('ghdl', '--synth', '--std=08', '-fsynopsys', f'--workdir={BUILD}', '--latches',
      '--out=verilog', *options, entity, stdout=output)
# GHDL specializes VHDL generics; remove only the redundant SV parameter association in the generated copy.
virtual = (ROOT / 'rtl/soc/minimig_virtual_top.v').read_text()
virtual = re.sub(r'TG68K\s*#\(.*?\)\s*tg68k', 'TG68K tg68k', virtual, count=1, flags=re.S)
(BUILD / 'minimig_virtual_top.v').write_text(virtual)
board = (ROOT / 'fpga' / args.board / 'minimig_board.vh').read_text()
board = board.replace('`define MINIMIG_ECP5_BLITTER_DSP', '// Use equivalent arithmetic in simulation.')
(BUILD / 'minimig_board.vh').write_text(board)
ldf = next((ROOT / 'fpga' / args.board).glob('*.ldf'))
hdl = []
skip = {'minimig_icepi-zero_top.sv', 'minimig_virtual_top.v', 'mistle_companion.sv',
    'mistle_native_osd.v', 'sysctrl.v', 'mcu_spi.v', 'hid.v', 'mistle_osd.sv',
    'bitplane_ram.v', 'sprite_ram.v', 'dpram_be_1024x32.v', 'spram_be_512x32.v',
    'denise_colortable_ram_mf.v', 'sector_dpram.v', 'paula_floppy_dma_buf.v',
    'flash_dspi.v', 'flash_dspi_reader.sv', 'flash_boot.sv'}
for item in ET.parse(ldf).findall('.//Source'):
  path = (ldf.parent / item.get('name')).resolve()
  if path.suffix in ('.v', '.sv') and path.name not in skip: hdl.append(path)
hdl += [BUILD / 'minimig_virtual_top.v', BUILD / 'TG68K.v', BUILD / 'audiofilter.v', BUILD / 'AudioMix.v',
    SIM / 'clock_model.sv', SIM / 'sdr_chip_model.v', SIM / 'minimig_tb.sv',
    SIM / 'ebr_models.sv', SIM / 'bitplane_ram.v', SIM / 'sprite_ram.v']
cflags = subprocess.check_output(['sdl2-config', '--cflags'], text=True).strip()
ldflags = subprocess.check_output(['sdl2-config', '--libs'], text=True).strip()
run('verilator', '--cc', '--exe', '--build', '-j', args.j, '--no-timing', '--trace-fst',
  '-Wno-fatal', '-Wno-BLKANDNBLK', '-Wno-MULTIDRIVEN', '-Dmixed_hdl',
  f'-I{BUILD}', f'-I{ROOT / "rtl/soc"}', f'-I{ROOT / "rtl/minimig"}',
  '--top-module', 'minimig_tb', '--Mdir', BUILD / 'obj_dir', '-o', BUILD / 'minimig-sim',
  *hdl, SIM / 'main.cpp', SIM / 'sd_card.cpp', '-CFLAGS', cflags + ' -I' + str(SIM), '-LDFLAGS', ldflags)
# vim: ts=2 sw=2 tw=120 et
