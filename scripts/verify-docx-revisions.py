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
print('DOCX text revisions: authors, dates, accepted/rejected Unicode text, links and note parts verified')
