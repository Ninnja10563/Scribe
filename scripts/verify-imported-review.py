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

for mode in ('Accepted', 'Rejected'):
    pdf = pymupdf.open(folder / ('ImportedObjectReview' + mode + '.pdf'))
    assert len(pdf) == 1
    page = pdf[0]
    assert 'Objects' in page.get_text()
    assert len(page.get_images()) == (1 if mode == 'Accepted' else 0)
    assert ('Reviewed note payload' in page.get_text()) == (mode == 'Rejected')
    if mode == 'Accepted':
        image = page.get_images()[0]
        bounds = page.get_image_rects(image[0])[0]
        assert abs(bounds.width - 64) < 0.1 and abs(bounds.height - 32) < 0.1
print('Imported Office object review: accepted image geometry and rejected note payload verified')

for mode in ('Accepted', 'Rejected'):
    pdf = pymupdf.open(folder / ('ImportedParagraphReview' + mode + '.pdf'))
    assert len(pdf) == 1
    page = pdf[0]
    assert not page.get_images()
    # Search logical text while expanding the font's fi ligature.
    search_flags = pymupdf.TEXT_DEHYPHENATE | pymupdf.TEXT_PRESERVE_WHITESPACE | pymupdf.TEXT_MEDIABOX_CLIP
    for prefix in ('Body', 'Note'):
        if mode == 'Accepted':
            assert len(page.search_for(prefix + ' first' + prefix + ' second', flags=search_flags)) == 1
        else:
            first = page.search_for(prefix + ' first', flags=search_flags)
            second = page.search_for(prefix + ' second', flags=search_flags)
            assert len(first) == len(second) == 1
            assert second[0].y0 - first[0].y0 > 5, (mode, prefix, first, second)
print('Imported Office paragraph review: body/note joins and retained boundaries verified')
