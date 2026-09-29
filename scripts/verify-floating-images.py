#!/usr/bin/env python3
"""Independently check floating image geometry, text preservation and PDF paint order."""
import argparse
import json
from pathlib import Path
import pymupdf

parser = argparse.ArgumentParser()
parser.add_argument('native', type=Path)
parser.add_argument('--notes', action='store_true', help='Also verify the native repeated-asset/footnote fixture')
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
if args.notes:
    with pymupdf.open(args.native / 'FloatingImage-notes.pdf') as pdf:
        text = ' '.join(' '.join(page.get_text().split()) for page in pdf)
        assert text.count('FloatingCitation') == 1 and text.count('Source information.') == 20, 'Footnote content lost'
        page = pdf[0]
        images = page.get_image_info(hashes=True)
        assert len(images) == 2 and images[0]['digest'] == images[1]['digest'], 'Repeated asset occurrences changed'
        expected = [(92,152,212,212), (332,312,452,372)]
        for image, frame in zip(images, expected):
            assert all(abs(a-b) < .1 for a,b in zip(image['bbox'], frame)), 'Repeated occurrence placement changed'
            bounds = pymupdf.Rect(image['bbox'])
            assert all(not pymupdf.Rect(word[:4]).intersects(bounds) for word in page.get_text('words')), 'Image overlaps body or footnote text'
        citation = page.search_for('FloatingCitation')
        assert len(citation) == 1 and citation[0].y0 > max(frame[3] for frame in expected), 'Footnote detached from its reference page'
        # Read body separately: PDF reading order places the page-one note before page-two body.
        body = page.get_text(clip=pymupdf.Rect(0, 0, page.rect.width, citation[0].y0 - 2))
        body += ' ' + ' '.join(later.get_text() for later in list(pdf)[1:])
        assert ' '.join(body.split()).count('Text continues through the page.') == 80, 'Body text lost beside images or notes'
        report['notes'] = {'pages': len(pdf), 'image_bounds': expected, 'citation_y': citation[0].y0}
(args.native / 'floating-image-measurements.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
