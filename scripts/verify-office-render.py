#!/usr/bin/env python3
"""Render Scribe's actual DOCX exports in LibreOffice and inspect the resulting PDFs.
Development validation only; LibreOffice is not an application dependency.
"""
import argparse
import json
import math
from pathlib import Path
import subprocess

from docx import Document
import pymupdf

parser = argparse.ArgumentParser()
parser.add_argument('build', type=Path)
args = parser.parse_args()
build = args.build.resolve()
output = build / 'office-render'
output.mkdir(parents=True, exist_ok=True)
sources = [build / 'smoke/Smoke.docx', build / 'schema/MergedTable.docx', build / 'schema/DocumentProperties.docx', build / 'schema/ImageAdjustments.docx', build / 'schema/ImageRotation.docx', build / 'schema/StyleOverrides.docx', build / 'schema/ScriptTypography.docx', build / 'schema/ParagraphIndents.docx']
result = subprocess.run([
    'libreoffice', '-env:UserInstallation=' + (output / 'profile').as_uri(),
    '--headless', '--norestore', '--convert-to', 'pdf:writer_pdf_Export',
    '--outdir', str(output), *map(str, sources),
], check=True, timeout=90, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
(output / 'conversion.log').write_text(result.stdout)
print(result.stdout)
report = {}
for source in sources:
    path = output / (source.stem + '.pdf')
    assert path.is_file() and path.stat().st_size > 100, f'Missing converted PDF: {path}'
    pdf = pymupdf.open(path)
    text = '\n'.join(page.get_text() for page in pdf)
    word = Document(source)
    assert pdf.metadata['title'] == word.core_properties.title, f'Lost title in {source.name}'
    report[source.name] = {'pages': len(pdf), 'metadata': pdf.metadata}
    if source.stem == 'Smoke':
        assert 5 <= len(pdf) <= 40, 'Unexpected smoke document pagination'
        for number in range(1, 81):
            assert f'Paragraph {number}.' in text, f'Missing paragraph {number}'
        for label in ('Scribe', 'Contents', 'Styles and outline', 'Flowing pages'):
            assert label in text, f'Missing {label}'
        assert any(page.get_images() for page in pdf), 'Missing inline image'
    elif source.stem == 'MergedTable':
        assert len(pdf) == 1
        for row in range(3):
            for column in range(3):
                assert text.count(f'Cell {row},{column}') == 1, f'Missing or duplicate merged cell {row},{column}'
        first = pdf[0].search_for('Cell 0,0')[0]
        right = pdf[0].search_for('Cell 0,2')[0]
        assert right.x0 - first.x0 > 200, 'Merged width was not retained'
    for page in pdf:
        for word_box in page.get_text('words'):
            assert page.rect.contains(pymupdf.Rect(word_box[:4])), f'Text outside a physical page in {source.name}'
    pdf[0].get_pixmap(matrix=pymupdf.Matrix(1, 1)).save(output / (source.stem + '.png'))
(output / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False))
print('LibreOffice rendered all DOCX exports with expected text, images, metadata and merged geometry.')

# Compare real native and Office-rendered image geometry and colors, not only XML attributes.
for name, angle in [('ImageAdjustments', 90), ('ImageRotation', 30)]:
    for label, path in [('Native', build / ('schema/' + name + '.pdf')), ('LibreOffice', output / (name + '.pdf'))]:
        pdf = pymupdf.open(path)
        assert len(pdf) == 1, f'{label}: unexpected adjusted image pagination'
        page = pdf[0]
        pix = page.get_pixmap(matrix=pymupdf.Matrix(1, 1), alpha=False)
        raw = pix.samples
        points = []
        for y in range(pix.height):
            for x in range(pix.width):
                i = (y * pix.width + x) * pix.n
                color = raw[i:i+3]
                if max(color) > 180 and max(color) - min(color) > 60:
                    points.append((x, y))
        assert points, f'{label}: adjusted image is missing'
        x0, y0 = map(min, zip(*points)); x1, y1 = map(max, zip(*points))
        c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        width, height = c*150+s*100, s*150+c*100
        assert abs(x1-x0+1-width) <= 3 and abs(y1-y0+1-height) <= 3, f'{label}: wrong rotated frame {(x0,y0,x1,y1)}'
        for x, y, expected in [(25,25,(255,128,128)), (100,25,(128,255,128)), (25,75,(128,128,255)), (100,75,(255,255,128))]:
            dx = round(c*(x-75)-s*(y-50)+width/2)
            dy = round(s*(x-75)+c*(y-50)+height/2)
            i = ((y0+dy)*pix.width+x0+dx)*pix.n
            actual = tuple(raw[i:i+3])
            assert all(abs(a-b) <= 30 for a,b in zip(actual,expected)), f'{label} {angle}°: crop/rotation/opacity mismatch {actual} != {expected}'
        following = page.search_for('After adjusted image.')[0]
        assert following.y0 >= y1-1, f'{label}: text overlaps adjusted image'
        assert abs(following.x0-x0) <= 4, f'{label}: rotated image shifts away from paragraph margin'
        pix.save(output / (label + '-' + name + '.png'))
print('Native and LibreOffice PDFs preserve cropped clockwise image geometry, opacity, colors and following text flow at 30° and 90°.')

for label, path in [('Native', build / 'schema/StyleOverrides.pdf'), ('LibreOffice', output / 'StyleOverrides.pdf')]:
    pdf = pymupdf.open(path)
    page = pdf[0]
    pix = page.get_pixmap(matrix=pymupdf.Matrix(2, 2), alpha=False)
    raw = pix.samples
    for text, expected in [('INHERITED', 'yellow'), ('NO HIGHLIGHT', None), ('DIRECT', 'red')]:
        boxes = page.search_for(text)
        assert len(boxes) == 1, f'{label}: missing styled text {text}'
        rect = boxes[0] * 2
        # Inspect inside the text bounds, excluding the adjacent paragraph separator.
        # TextKit can paint a highlighted newline through the remaining line width.
        rect = pymupdf.Rect(rect.x0 + 2, rect.y0 + 2, rect.x1 - 2, rect.y1 - 2)
        yellow = red = 0
        for y in range(max(0,int(rect.y0)), min(pix.height,int(rect.y1)+1)):
            for x in range(max(0,int(rect.x0)), min(pix.width,int(rect.x1)+1)):
                i = (y*pix.width+x)*pix.n
                r,g,b = raw[i:i+3]
                yellow += r > 180 and g > 180 and b < 90
                red += r > 180 and g < 90 and b < 90
        if expected == 'yellow': assert yellow > 20, f'{label}: missing inherited highlight'
        elif expected == 'red': assert red > 20, f'{label}: missing direct highlight'
        else: assert yellow + red == 0, f'{label}: explicit highlight removal was lost'
    pix.save(output / (label + '-StyleOverrides.png'))
print('Native and LibreOffice preserve inherited, explicitly removed and directly overridden style highlighting.')

for label, path in [('Native', build / 'schema/ScriptTypography.pdf'), ('LibreOffice', output / 'ScriptTypography.pdf')]:
    pdf = pymupdf.open(path)
    page = pdf[0]
    spans = [span for block in page.get_text('dict')['blocks'] if 'lines' in block for line in block['lines'] for span in line['spans']]
    base = next(s for s in spans if s['text'].strip() == 'Base')
    up = next(s for s in spans if s['text'].strip() == 'SUP')
    down = next(s for s in spans if s['text'].strip() == 'SUB')
    assert abs(base['size']-20) < 0.1, f'{label}: logical base font size changed'
    assert up['size'] < base['size']*0.8 and down['size'] < base['size']*0.8, f'{label}: script glyphs were not reduced'
    assert up['origin'][1] < base['origin'][1]-1, f'{label}: superscript was not raised'
    assert down['origin'][1] > base['origin'][1]+1, f'{label}: subscript was not lowered'
    if label == 'Native':
        assert abs(base['origin'][1]-up['origin'][1]-7) < 0.1, 'Native superscript baseline offset was applied twice'
        assert abs(down['origin'][1]-base['origin'][1]-4) < 0.1, 'Native subscript baseline offset was applied twice'
    assert not page.get_images(), f'{label}: script text should remain vector text'
    page.get_pixmap(matrix=pymupdf.Matrix(2, 2)).save(output / (label + '-ScriptTypography.png'))
print('Native and LibreOffice retain the logical font size and render vector superscripts/subscripts above and below the baseline.')

for label, path in [('Native', build / 'schema/ParagraphIndents.pdf'), ('LibreOffice', output / 'ParagraphIndents.pdf')]:
    pdf = pymupdf.open(path)
    assert len(pdf) == 1, f'{label}: unexpected paragraph-indent pagination'
    page = pdf[0]
    boxes = {text: page.search_for(text)[0] for text in ['FIRST', 'CONTINUE', 'HANG', 'INDENT', 'RIGHT right-aligned paragraph.']}
    assert abs(boxes['FIRST'].x0-boxes['CONTINUE'].x0-36) < 1, f'{label}: first-line indent lost'
    assert abs(boxes['INDENT'].x0-boxes['HANG'].x0-48) < 1, f'{label}: hanging indent lost'
    assert abs(boxes['CONTINUE'].x0-72) < 1, f'{label}: ordinary left margin shifted'
    assert abs(boxes['RIGHT right-aligned paragraph.'].x1-(page.rect.width-72-36)) < 2, f'{label}: right indent lost'
    page.get_pixmap(matrix=pymupdf.Matrix(1, 1)).save(output / (label + '-ParagraphIndents.png'))
print('Native and LibreOffice PDFs retain first-line, hanging and right paragraph indents authored through the ruler.')
