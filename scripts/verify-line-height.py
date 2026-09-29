#!/usr/bin/env python3
"""Measure actual baseline distances in native and independently rendered Office PDFs."""
import argparse
import json
from pathlib import Path
import pymupdf

parser = argparse.ArgumentParser()
parser.add_argument('native', type=Path)
parser.add_argument('--office', type=Path)
args = parser.parse_args()
report = {}
for engine, folder, prefix in [('Native', args.native, 'LineHeightNative-')] + ([('LibreOffice', args.office, 'LineHeight-')] if args.office else []):
    distances = {}
    for mode in ('natural', 'multiple', 'minimum', 'exact'):
        path = folder / (prefix + mode + '.pdf')
        with pymupdf.open(path) as pdf:
            assert len(pdf) == 1, f'{path}: unexpected pagination'
            spans = [span for block in pdf[0].get_text('dict')['blocks'] if 'lines' in block for line in block['lines'] for span in line['spans']]
            baselines = []
            for text in ('First line', 'Second line', 'Third line'):
                matches = [span for span in spans if span['text'] == text]
                assert len(matches) == 1, f'{path}: missing or duplicate {text}'
                baselines.append(matches[0]['origin'][1])
            gaps = [b - a for a, b in zip(baselines, baselines[1:])]
            assert abs(gaps[0] - gaps[1]) < 0.1, f'{path}: inconsistent spacing {gaps}'
            distances[mode] = gaps[0]
            pdf[0].get_pixmap().save(folder / (prefix + mode + '.png'))
    for mode in ('minimum', 'exact'):
        assert abs(distances[mode] - 24) < 0.1, f'{engine}: {mode} {distances}'
    assert abs(distances['multiple'] / distances['natural'] - 1.5) < 0.03, f'{engine}: multiplier {distances}'
    report[engine] = distances
output = args.office or args.native
(output / 'line-height-measurements.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
