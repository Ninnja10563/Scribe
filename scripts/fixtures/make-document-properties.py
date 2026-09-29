"""Original metadata/language fixture; requires python-docx 1.2.0."""
from pathlib import Path
from docx import Document
from docx.oxml.ns import qn

doc = Document()
doc.core_properties.title = 'Independent résumé & 東京'
doc.core_properties.author = 'Zoë Example'
doc.core_properties.language = 'en-GB'
doc.add_paragraph('Colour is checked using British English.')
language = doc.styles.element.find('.//' + qn('w:docDefaults')).find('.//' + qn('w:lang'))
language.set(qn('w:val'), 'en-GB')
doc.save(Path(__file__).resolve().parents[2] / 'Tests/ImportExportTests/Fixtures/DocumentProperties.docx')
