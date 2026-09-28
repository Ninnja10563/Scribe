"""Original independent OPC fixture. Requires python-docx 1.2.0; no Word automation."""
from pathlib import Path
from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn


def element(tag, **attributes):
    node = OxmlElement('w:' + tag)
    for key, value in attributes.items():
        node.set(qn('w:' + key), str(value))
    return node


doc = Document()
numbering = doc.part.numbering_part.element
abstract = element('abstractNum', abstractNumId=42)
for index, format_name in [(0, 'upperRoman'), (1, 'lowerLetter')]:
    level = element('lvl', ilvl=index)
    for child in [element('start', val=1), element('numFmt', val=format_name), element('lvlText', val=f'%{index + 1}.')]:
        level.append(child)
    abstract.append(level)
# Insert abstract definitions before concrete instances as required by the schema.
first_num = numbering.find(qn('w:num'))
first_num.addprevious(abstract)
for identifier, start in [(101, 4), (205, 9)]:
    instance = element('num', numId=identifier)
    instance.append(element('abstractNumId', val=42))
    override = element('lvlOverride', ilvl=0)
    override.append(element('startOverride', val=start))
    instance.append(override)
    numbering.append(instance)

samples = [('First item', 101, 0), ('Nested detail', 101, 1), ('Body paragraph', None, 0), ('Continued item', 101, 0), ('Restarted item', 205, 0)]
for text, number, depth in samples:
    paragraph = doc.add_paragraph(text)
    if number:
        properties = paragraph._p.get_or_add_pPr()
        num = element('numPr')
        num.append(element('ilvl', val=depth))
        num.append(element('numId', val=number))
        properties.append(num)

output = Path(__file__).resolve().parents[2] / 'Tests/ImportExportTests/Fixtures/Numbering.docx'
doc.save(output)
