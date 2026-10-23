#!/usr/bin/env python3
"""Repeatable regressions for the real MiSTle/IDE/configuration/ROM interfaces."""
from pathlib import Path
import argparse
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('tests', nargs='*',
    choices=['storage', 'control', 'kickstart', 'sdram', 'flash', 'flash_dspi'])
args = parser.parse_args()
tests = args.tests or ['storage', 'control', 'kickstart', 'sdram', 'flash', 'flash_dspi']
files = {
  'storage': ['rtl/mistle/sdc_controller.sv', 'rtl/minimig/ide.v', 'rtl/minimig/ide_fifo.v'],
  'control': ['rtl/mistle/mcu_spi.v', 'rtl/mistle/sysctrl.v', 'rtl/mistle/mistle_osd.sv', 'rtl/minimig/userio_config.v'],
  'kickstart': ['rtl/mistle/kickstart_loader.sv'],
  'sdram': ['sim/sdr_chip_model.v'],
  'flash': ['rtl/mistle/flash_boot.sv'],
  'flash_dspi': ['rtl/mistle/flash_boot.sv', 'rtl/mistle/flash_dspi_reader.sv', 'rtl/mistle/flash_dspi.v'],
}
with tempfile.TemporaryDirectory(prefix='minimig-mistle-tests-') as work:
  for name in tests:
    binary = Path(work) / name
    subprocess.run(['iverilog', '-g2012', '-DENABLE_RTC', '-I', str(ROOT / 'config'),
            '-s', name + '_tb', '-o', str(binary), str(ROOT / f'bench/mistle/{name}_tb.sv'),
            *(str(ROOT / f) for f in files[name])], check=True)
    subprocess.run(['vvp', str(binary)], cwd=ROOT / 'config', check=True)
# vim: ts=2 sw=2 tw=120 et
