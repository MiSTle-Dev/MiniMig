#!/usr/bin/env python3
"""Summarize routed timing and optionally check the inherited TG68K constraints."""
import argparse
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def cpu_constraints(path):
  return [line for line in path.read_text().splitlines()
          if 'tg68k' in line and ('MULTICYCLE' in line or 'set_multicycle_path' in line)
          and 'cfide' not in line and 'amiga_buffer' not in line]

def normalize(line):
  return re.sub(r'\s+', '', re.sub(r'(\d+)\.0+\b', r'\1', line))

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--baseline', type=Path, help='original icepi-zero-minimig tree')
args = parser.parse_args()

for board in ('icepi-zero', 'icepi-zero-xl'):
  directory = ROOT / 'fpga' / board
  print(board)
  if args.baseline:
    for suffix in ('.sdc', '.lpf'):
      name = ('minimig_' + board if suffix == '.sdc' else board) + suffix
      actual = cpu_constraints(directory / name)
      expected = cpu_constraints(args.baseline / 'fpga' / board / name)
      if actual != expected:
        raise SystemExit(f'{board}: inherited TG68K constraints changed in {suffix}')
      print(f'  {suffix}: {len(actual)} inherited TG68K multicycle lines unchanged')
  preferences = list(directory.glob('Minimig_IcePi-Zero*/*.prf'))
  if preferences:
    expected = Counter(map(normalize, cpu_constraints(directory / (board + '.lpf'))))
    mapped = Counter(map(normalize, cpu_constraints(preferences[0])))
    if mapped - expected:
      raise SystemExit(f'{board}: unexpected TG68K budget in mapped preferences')
    print(f'  mapped TG68K preferences: {sum(mapped.values())}; '
          f'{sum((expected - mapped).values())} source preferences not emitted by mapper')
  reports = list(directory.glob('Minimig_IcePi-Zero*/*.twr'))
  if not reports:
    print('  no routed report yet')
    continue
  report = reports[0]
  modified = datetime.fromtimestamp(report.stat().st_mtime, timezone.utc).isoformat(timespec='seconds')
  print(f'  report timestamp: {modified}')
  report_text = report.read_text()
  totals = re.search(r'Timing errors:\s*(\d+) \(setup\),\s*(\d+) \(hold\)', report_text)
  if totals:
    print(f'  TRACE totals: {totals[1]} setup, {totals[2]} hold violations')
  entries = []
  for block in re.split(r'(?=\n(?:Error:|Passed:|Blocked:|Preference:|={8,}))', report_text):
    if not block.lstrip().startswith('Error:'):
      continue
    source = re.search(r'Source:.*? (\S+)  \(from', block)
    destination = re.search(r'Destination:.*? (\S+)  \(to', block)
    if source and destination:
      entries.append((source[1], destination[1]))
  print(f'  {len(entries)} detailed failing entries (report limit applies; endpoint pairs may repeat)')
  for label, predicate in (
      ('menu screen mode', lambda a, b: 'companion/control/system_video_screen' in a
       or 'USERIO1/control/screen_mode' in a),
      ('RTG OSD first enable stage', lambda a, b: b == 'osd_rtg/enable_sync[0]'),
      ('native OSD EBR to HDMI', lambda a, b: a.startswith('native_osd/buffer') and b.startswith('hdmi_inst/')),
      ('Companion OSD enable', lambda a, b: a == 'companion/osd/enabled'),
      ('disk length to Agnus', lambda a, b: '/pf1/dsklen' in a and '/AGNUS1/' in b),
      ('RTG acknowledgement', lambda a, b: b.endswith('/rtg_reg_ack_d'))):
    print(f'  {label}: {sum(predicate(a, b) for a, b in entries)} failing entries')
  for (source, destination), count in Counter(entries).most_common(8):
    print(f'  {count:4}: {source} -> {destination}')
  print(f'  report: {report.relative_to(ROOT)}')

# vim: ts=2 sw=2 tw=120 et
