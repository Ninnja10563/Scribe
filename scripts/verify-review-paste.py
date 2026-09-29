"""Inspect native grouped-review files and the PDF from an actual RTF paste."""
import json
import sys
from pathlib import Path

import pymupdf

folder = Path(sys.argv[1])
models = {state: json.loads((folder / f'{state}RichPaste.scribe').read_text())
          for state in ['Grouped', 'Accepted', 'Rejected']}
def paragraphs(model):
    return model['sections'][0]['paragraphs']
def texts(model):
    return [''.join(run['text'] for run in paragraph['runs']) for paragraph in paragraphs(model)]
def walk(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)

assert texts(models['Grouped']) == texts(models['Accepted']) == ['AX', 'YB']
assert texts(models['Rejected']) == ['AB']
identities = [item for item in walk(models['Grouped']) if item.get('groupID') and 'author' in item]
assert len({item['groupID'] for item in identities}) == 1, 'Paste components lost their shared group'
assert len({item['id'] for item in identities}) == 2, 'Insertion and formatting must retain distinct identities'
assert len({(item['author']['id'], item['author']['name'], item['date']) for item in identities}) == 1
for state in ['Accepted', 'Rejected']:
    assert not any(item.get(key) for item in walk(models[state]) for key in ['review', 'breakReview', 'formattingReview']), f'{state}: unresolved review remains'
assert [p['formatting']['alignment'] for p in paragraphs(models['Accepted'])] == ['center', 'right']
assert paragraphs(models['Rejected'])[0].get('formatting') is None, 'Rejection froze a paragraph override'
assert all(not run['format'] for run in paragraphs(models['Rejected'])[0]['runs']), 'Rejection froze character formatting'
with pymupdf.open(folder / 'GroupedRichPaste.pdf') as document:
    assert len(document) == 1
    page = document[0]
    # search_for returns separate rectangles for mixed-size spans within a
    # single match. Word extraction gives the complete adjacent text bounds.
    words = page.get_text('words')
    assert [word[4] for word in words] == ['AX', 'YB'], 'Pasted or original text was lost/duplicated'
    a, b = [pymupdf.Rect(word[:4]) for word in words]
    spans = [span for block in page.get_text('dict')['blocks'] if 'lines' in block
             for line in block['lines'] for span in line['spans']]
    assert [(span['text'], span['size']) for span in spans] == [('A', 12), ('X', 18), ('Y', 15), ('B', 12)]
    assert spans[1]['flags'] & 16, 'Pasted bold formatting was lost'
    settings = models['Grouped']['sections'][0]['page']
    center = (settings['left'] + settings['width'] - settings['right']) / 2
    assert abs((a.x0 + a.x1) / 2 - center) < 1, 'Centered paragraph is misplaced'
    assert abs(b.x1 - (settings['width'] - settings['right'])) < 1, 'Right-aligned paragraph is misplaced'
    assert not page.get_images(), 'Rich paste should remain vector text'
print('Native revision groups, acceptance/rejection, inherited formatting and rendered RTF paragraph alignment verified.')
