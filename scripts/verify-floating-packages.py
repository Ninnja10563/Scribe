#!/usr/bin/env python3
"""Inspect actual OPC anchored drawings independently of the Swift writer."""
import argparse
from pathlib import Path
from zipfile import ZipFile
from lxml import etree

parser = argparse.ArgumentParser()
parser.add_argument('schema', type=Path)
args = parser.parse_args()
ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
      'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
for mode in ('square', 'behindText', 'inFrontOfText'):
    path = args.schema / f'FloatingImage-{mode}.docx'
    with ZipFile(path) as package:
        root = etree.fromstring(package.read('word/document.xml'))
        anchors = root.xpath('//wp:anchor', namespaces=ns)
        assert len(anchors) == 1 and not root.xpath('//wp:inline', namespaces=ns)
        anchor = anchors[0]
        assert anchor.get('simplePos') == '0'
        assert anchor.get('behindDoc') == ('1' if mode == 'behindText' else '0')
        assert all(anchor.get(key) == '101600' for key in ('distT', 'distB', 'distL', 'distR'))
        for direction, offset in [('H', 254000), ('V', 1016000)]:
            position = anchor.find(f'wp:position{direction}', ns)
            assert position.get('relativeFrom') == 'margin'
            assert int(position.find('wp:posOffset', ns).text) == offset
        extent = anchor.find('wp:extent', ns)
        assert (int(extent.get('cx')), int(extent.get('cy'))) == (1524000, 762000)
        wrap = anchor.find('wp:wrapSquare' if mode == 'square' else 'wp:wrapNone', ns)
        assert wrap is not None
        if mode == 'square':
            assert wrap.get('wrapText') == 'bothSides'
        rel_id = anchor.xpath('.//a:blip/@r:embed', namespaces=ns)[0]
        relationships = etree.fromstring(package.read('word/_rels/document.xml.rels'))
        relation = next(node for node in relationships if node.get('Id') == rel_id)
        assert relation.get('Type') == ns['r'] + '/image'
        assert package.read('word/' + relation.get('Target')).startswith(b'\x89PNG\r\n\x1a\n')
        text = ''.join(root.xpath('//w:t/text()', namespaces=ns))
        assert text.count('Text continues through the page.') == 80
    print(f'{path.name}: anchored geometry, wrapping, relationship, asset and text verified')
