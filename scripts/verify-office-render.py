#!/usr/bin/env python3
"""Render Scribe's actual DOCX exports in LibreOffice and inspect the resulting PDFs.
Development validation only; LibreOffice is not an application dependency.
"""
import argparse
import json
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
sources = [build / 'smoke/Smoke.docx', build / 'schema/MergedTable.docx', build / 'schema/DocumentProperties.docx']
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
print('LibreOffice rendered all three DOCX exports with expected text, image, metadata and merged geometry.')
