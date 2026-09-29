#!/usr/bin/env python3
"""Check native PDF output after actual Office revision import."""
from pathlib import Path
import sys
import pymupdf

folder = Path(sys.argv[1])
for mode, expected, absent in [('Marked', ('Old', 'New', 'stable'), ()),
                               ('Accepted', ('New', 'stable'), ('Old',)),
                               ('Rejected', ('Old', 'stable'), ('New',))]:
    pdf = pymupdf.open(folder / ('ImportedReview' + mode + '.pdf'))
    assert len(pdf) == 1
    page = pdf[0]
    assert not page.get_images(), 'Imported review text was rasterized'
    text = page.get_text()
    assert all(value in text for value in expected), (mode, text)
    assert all(value not in text for value in absent), (mode, text)
    spans = [span for block in page.get_text('dict')['blocks'] if 'lines' in block
             for line in block['lines'] for span in line['spans']]
    stable = next(span for span in spans if 'stable' in span['text'])
    size, color, bold = (14, 0x123456, False) if mode == 'Rejected' else (18, 0x654321, True)
    if mode == 'Marked':
        assert any(path['color'] and all(abs(a-b) < 0.001 for a,b in zip(path['color'], (0.16, 0.32, 0.64)))
                   and path['dashes'] != '[] 0' for path in page.get_drawings()), 'Missing dotted formatting mark'
    assert abs(stable['size'] - size) < 0.1, (mode, stable)
    assert all(abs(((stable['color'] >> shift) & 255) - ((color >> shift) & 255)) <= 1 for shift in (0, 8, 16)), (mode, stable)
    assert bool(stable['flags'] & 16) == bold, (mode, stable)
    assert stable['flags'] & 2, (mode, stable)
    for word in page.get_text('words'):
        assert page.rect.contains(pymupdf.Rect(word[:4])), (mode, word)
print('Imported Office review: native vector text, decisions and historical formatting verified')
