#!/usr/bin/env python3
"""Independently check floating image geometry, text preservation and PDF paint order."""
import argparse
import json
from pathlib import Path
import pymupdf

parser = argparse.ArgumentParser()
parser.add_argument('native', type=Path)
args = parser.parse_args()
report = {}
expected_text = 'Before after anchor. ' + 'Text continues through the page. ' * 80
for mode in ('behindText', 'inFrontOfText', 'square'):
    path = args.native / f'FloatingImage-{mode}.pdf'
    with pymupdf.open(path) as pdf:
        assert len(pdf) == 1, f'{mode}: unexpected page count'
        page = pdf[0]
        text = ' '.join(page.get_text().split())
        assert text == ' '.join(expected_text.split()), f'{mode}: missing or reordered text'
        images = page.get_image_info()
        assert len(images) == 1, f'{mode}: unexpected image count'
        bounds = pymupdf.Rect(images[0]['bbox'])
        assert all(abs(a-b) < .1 for a,b in zip(bounds, (92,152,212,212))), f'{mode}: {bounds}'
        assert (images[0]['width'], images[0]['height']) == (32,16), 'Original image resolution changed'
        painting = page.get_bboxlog()
        image_index = next(i for i,(kind,_) in enumerate(painting) if kind == 'fill-image')
        text_indices = [i for i,(kind,_) in enumerate(painting) if kind == 'fill-text']
        assert text_indices, 'Text must remain vector text'
        if mode == 'behindText':
            assert image_index < min(text_indices), 'Background image painted above body text'
        else:
            assert image_index > max(text_indices), 'Foreground image painted below body text'
        if mode == 'square':
            exclusion = pymupdf.Rect(84,144,220,220)
            words = page.get_text('words')
            assert all(not pymupdf.Rect(word[:4]).intersects(bounds) for word in words), 'Text overlaps square image'
            alongside = [word for word in words if word[1] >= exclusion.y0 and word[3] <= exclusion.y1]
            assert alongside and all(word[0] >= exclusion.x1 - .1 for word in alongside), 'Missing right-hand wrapping'
            assert any(word[0] < 73 and word[1] > exclusion.y1 for word in words), 'Text never returns to full width'
        report[mode] = {'pages': len(pdf), 'image_bounds': list(bounds), 'vector_text_operations': len(text_indices), 'words': len(text.split())}
(args.native / 'floating-image-measurements.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
