#!/usr/bin/env python3
"""Check real native decisions and independently materialized Office pPr decisions."""
import argparse
import json
from pathlib import Path
import subprocess
from zipfile import ZipFile, ZIP_DEFLATED
from lxml import etree
import pymupdf

parser = argparse.ArgumentParser()
parser.add_argument('schema', type=Path)
parser.add_argument('--office', type=Path)
args = parser.parse_args()
report = {}

def measure(path, expected_gap, expected_pages=None, expected_left=None):
    with pymupdf.open(path) as pdf:
        if expected_pages is not None:
            assert len(pdf) == expected_pages, (path, len(pdf))
        spans = [span for page in pdf for block in page.get_text('dict')['blocks'] if 'lines' in block for line in block['lines'] for span in line['spans']]
        selected = []
        for text in ('First line', 'Second line', 'Third line'):
            matches = [span for span in spans if span['text'] == text]
            assert len(matches) == 1, (path, text, matches)
            selected.append(matches[0])
        gaps = [b['origin'][1] - a['origin'][1] for a, b in zip(selected, selected[1:])]
        assert all(abs(gap - expected_gap) < 0.15 for gap in gaps), (path, gaps)
        left = selected[0]['origin'][0]
        if expected_left is not None:
            assert abs(left - expected_left) < 0.2, (path, left)
        else:
            assert left > 350, (path, 'right alignment missing', left)
            edges = [span['bbox'][2] for span in selected]
            assert max(edges) - min(edges) < 0.2, (path, edges)
        report[path.stem] = {'pages': len(pdf), 'baselines': [s['origin'][1] for s in selected], 'first_x': left}
        for number, page in enumerate(pdf):
            page.get_pixmap().save(path.with_name(path.stem + '-' + str(number + 1) + '.png'))

measure(args.schema / 'ImportedParagraphFormattingAccepted.pdf', 28, expected_pages=2)
measure(args.schema / 'ImportedParagraphFormattingRejected.pdf', 21, expected_pages=1, expected_left=90)
if args.office:
    output = args.office.resolve(); output.mkdir(parents=True, exist_ok=True)
    with ZipFile(args.schema / 'ParagraphFormattingRevisions.docx') as archive:
        parts = {name: archive.read(name) for name in archive.namelist()}
    namespace = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    sources = []
    for accepting in (True, False):
        root = etree.fromstring(parts['word/document.xml'])
        changes = root.xpath('//w:pPrChange', namespaces=namespace)
        assert len(changes) == 1
        change = changes[0]; current = change.getparent()
        assert len(change) == 1 and change[0].tag == '{' + namespace['w'] + '}pPr'
        if accepting:
            current.remove(change)
        else:
            previous = change[0]; change.remove(previous)
            current.getparent().replace(current, previous)
        name = 'ParagraphFormattingAccepted' if accepting else 'ParagraphFormattingRejected'
        path = output / (name + '.docx')
        with ZipFile(path, 'w', compression=ZIP_DEFLATED) as archive:
            for part, data in parts.items():
                archive.writestr(part, etree.tostring(root) if part == 'word/document.xml' else data)
        sources.append(path)
    result = subprocess.run(['libreoffice', '-env:UserInstallation=' + (output / 'paragraph-revision-profile').as_uri(), '--headless', '--norestore', '--convert-to', 'pdf:writer_pdf_Export', '--outdir', str(output), *map(str, sources)], check=True, timeout=90, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (output / 'paragraph-revision-conversion.log').write_text(result.stdout)
    measure(output / 'ParagraphFormattingAccepted.pdf', 28)
    measure(output / 'ParagraphFormattingRejected.pdf', 21, expected_left=90)
(args.office or args.schema).joinpath('paragraph-formatting-measurements.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
