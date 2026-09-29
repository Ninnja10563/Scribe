#!/usr/bin/env python3
"""Check real revision packages independently of Scribe's reader/writer."""
from pathlib import Path
import sys
from zipfile import ZipFile
from lxml import etree

W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
NS = {'w': W[1:-1]}


def projected(element, accepting):
    if element.tag == W + ('del' if accepting else 'ins'):
        return ''
    if element.tag in (W + 't', W + 'delText'):
        return element.text or ''
    if element.tag == W + 'tab':
        return '\t'
    if element.tag == W + 'br':
        return '\f' if element.get(W + 'type') == 'page' else '\u2028'
    return ''.join(projected(child, accepting) for child in element)


folder = Path(sys.argv[1])
with ZipFile(folder / 'TextRevisions.docx') as package:
    root = etree.fromstring(package.read('word/document.xml'))
    annotations = root.xpath('//w:ins | //w:del', namespaces=NS)
    assert len(annotations) == 2
    assert len({x.get(W + 'id') for x in annotations}) == 2
    assert all(x.get(W + 'author') == 'A & B <Review>' for x in annotations)
    assert all(x.get(W + 'date') == '2023-11-14T22:13:20Z' for x in annotations)
    assert root.xpath('//w:hyperlink/w:ins/w:r/w:rPr/w:b', namespaces=NS)
    assert not root.xpath('//w:del//w:t | //w:ins//w:delText', namespaces=NS)
    assert projected(root, True) == 'Before New 👩🏽‍💻 & <text>After'
    assert projected(root, False) == 'BeforeOld\tline\u2028page\fendAfter'

with ZipFile(folder / 'NoteTextRevisions.docx') as package:
    ids = []
    for kind in ('footnote', 'endnote'):
        root = etree.fromstring(package.read(f'word/{kind}s.xml'))
        annotation = root.xpath('//w:ins | //w:del', namespaces=NS)
        assert len(annotation) == 2
        ids.extend(x.get(W + 'id') for x in annotation)
        assert projected(root, True) == f' {kind} new'
        assert projected(root, False) == f' {kind} old'
    assert len(set(ids)) == len(ids)
with ZipFile(folder / 'CommentTextRevisions.docx') as package:
    root = etree.fromstring(package.read('word/document.xml'))
    revisions = root.xpath('//w:ins', namespaces=NS)
    assert len(revisions) == len({x.get(W + 'id') for x in revisions}) == 3
    assert projected(root, True) == 'A😀BC'
    assert projected(root, False) == ''
    paragraph = root.find('.//' + W + 'p')
    start = paragraph.find(W + 'commentRangeStart')
    end = paragraph.find(W + 'commentRangeEnd')
    assert start.get(W + 'id') == end.get(W + 'id')
    assert projected(start.getnext(), True) == '😀'
with ZipFile(folder / 'OverlappingTextRevisions.docx') as package:
    root = etree.fromstring(package.read('word/document.xml'))
    insertion = root.find('.//' + W + 'ins')
    deletion = insertion.find(W + 'del')
    assert insertion.get(W + 'author') == 'A & B <Review>'
    assert deletion.get(W + 'author') == 'Second reviewer'
    assert insertion.get(W + 'id') != deletion.get(W + 'id')
    assert projected(root, True) == projected(root, False) == 'BeforeAfter'
    # Reject only the deletion, retaining the pending insertion.
    insertion.remove(deletion)
    insertion.extend(list(deletion))
    assert projected(root, True) == 'BeforetemporaryAfter'
    assert projected(root, False) == 'BeforeAfter'

with ZipFile(folder / 'ObjectRevisions.docx') as package:
    root = etree.fromstring(package.read('word/document.xml'))
    assert root.xpath('//w:ins/w:r/w:drawing', namespaces=NS)
    assert root.xpath('//w:del/m:oMath', namespaces={**NS, 'm': 'http://schemas.openxmlformats.org/officeDocument/2006/math'})
    assert root.xpath('//w:del/w:r/w:footnoteReference', namespaces=NS)
    assert len([x for x in package.namelist() if x.startswith('word/media/')]) == 1
    assert 'Retained note payload' in package.read('word/footnotes.xml').decode()

with ZipFile(folder / 'FormattingRevisions.docx') as package:
    root = etree.fromstring(package.read('word/document.xml'))
    current = root.find('.//' + W + 'rPr')
    previous = current.find(W + 'rPrChange/' + W + 'rPr')
    assert current.find(W + 'sz').get(W + 'val') == '36'
    assert previous.find(W + 'sz').get(W + 'val') == '28'
    assert current.find(W + 'b') is not None and previous.find(W + 'b') is None
    assert current.find(W + 'i') is not None and previous.find(W + 'i') is not None
    assert current.find(W + 'color').get(W + 'val') == '654321'
    assert previous.find(W + 'color').get(W + 'val') == '123456'
print('DOCX text revisions: authors, dates, accepted/rejected Unicode text, links and note parts verified')
