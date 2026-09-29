#!/usr/bin/env python3
"""Check structural review markers and unchanged body geometry in native PDFs."""
import sys
from pathlib import Path
from collections import Counter
import pymupdf

root = Path(sys.argv[1])
plain = pymupdf.open(root / "ReviewStructuralPlain.pdf")
assert plain[0].get_text().strip() == "Middle"
base = plain[0].search_for("Middle")[0]
for name in ("ReviewStructuralMarked", "ReviewStructural-footnote", "ReviewStructural-endnote"):
    document = pymupdf.open(root / (name + ".pdf"))
    assert len(document) == (2 if name.endswith("endnote") else 1)
    page = document[-1]
    spans = [span for block in page.get_text("dict")["blocks"] if "lines" in block
             for line in block["lines"] for span in line["spans"] if "¶" in span["text"]]
    assert Counter(span["text"] for span in spans) == Counter({"¶+": 1, "¶−": 1, "¶~": 2})
    assert len({round(span["bbox"][1], 1) for span in spans}) == 3
    colors = {"¶+": 0x14663B, "¶−": 0xAD2929, "¶~": 0x2952A3}
    for span in spans:
        x0, y0, x1, y1 = span["bbox"]
        assert 0 <= x0 < x1 <= 72, "Marker overlaps document content"
        assert 0 <= y0 < y1 <= page.rect.height - 72
        assert span["color"] == colors[span["text"]]
    if name == "ReviewStructuralMarked":
        actual = page.search_for("Middle")[0]
        assert all(abs(a - b) < 0.01 for a, b in zip(actual, base)), "Markers changed text geometry"
print("Structural markers verified in body, footnotes and endnotes; plain output and text geometry are unchanged.")
