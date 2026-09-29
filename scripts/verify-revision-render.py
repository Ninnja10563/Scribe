#!/usr/bin/env python3
"""Render revision states through LibreOffice, independent of Scribe layout."""
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED
from lxml import etree
import pymupdf

build = Path(sys.argv[1]).resolve()
output = build / 'office-render'
output.mkdir(parents=True, exist_ok=True)
source = build / 'schema/FormattingRevisions.docx'
namespace = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
with ZipFile(source) as package:
    parts = {name: package.read(name) for name in package.namelist()}

# Independently materialize each Office property decision, preserving all other
# OPC parts. These are test copies, not the application's interchange engine.
sources = [source]
for accepting in (True, False):
    root = etree.fromstring(parts['word/document.xml'])
    changes = root.xpath('//w:rPrChange', namespaces=namespace)
    assert len(changes) == 1
    for change in changes:
        current = change.getparent()
        if accepting:
            current.remove(change)
        else:
            previous = change[0]
            change.remove(previous)
            current.getparent().replace(current, previous)
    path = output / ('FormattingAccepted.docx' if accepting else 'FormattingRejected.docx')
    with ZipFile(path, 'w', compression=ZIP_DEFLATED) as package:
        for name, data in parts.items():
            package.writestr(name, etree.tostring(root) if name == 'word/document.xml' else data)
    sources.append(path)
result = subprocess.run([
    'libreoffice', '-env:UserInstallation=' + (output / 'revision-profile').as_uri(),
    '--headless', '--norestore', '--convert-to', 'pdf:writer_pdf_Export',
    '--outdir', str(output), *map(str, sources),
], check=True, timeout=90, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
(output / 'revision-conversion.log').write_text(result.stdout)
print(result.stdout)
for name, size, color, bold in [
    ('FormattingAccepted', 18, 0x654321, True),
    ('FormattingRejected', 14, 0x123456, False),
]:
    pdf = pymupdf.open(output / (name + '.pdf'))
    assert len(pdf) == 1
    spans = [span for block in pdf[0].get_text('dict')['blocks'] if 'lines' in block
             for line in block['lines'] for span in line['spans'] if 'Formatting history' in span['text']]
    assert len(spans) == 1, f'{name}: missing revision text'
    span = spans[0]
    assert abs(span['size'] - size) < 0.1, (name, span)
    assert span['color'] == color, (name, span)
    assert bool(span['flags'] & 16) == bold, (name, span)
    assert span['flags'] & 2, (name, span)  # Unchanged italic survives both decisions.
    pdf[0].get_pixmap().save(output / (name + '.png'))
assert (output / 'FormattingRevisions.pdf').is_file()
print('LibreOffice formatting revisions: accepted/rejected size, color, bold and retained italic verified')
