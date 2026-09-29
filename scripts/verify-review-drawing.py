#!/usr/bin/env python3
"""Inspect native screen marks and ensure they do not become PDF formatting."""
import sys
from pathlib import Path
import pymupdf

folder = Path(sys.argv[1])
pdf = pymupdf.open(folder / "ReviewDrawing.pdf")
assert len(pdf) == 1
page = pdf[0]
assert page.get_text().strip() == "Inserted / Deleted / Original / Formatted"
spans = [span for block in page.get_text("dict")["blocks"] if "lines" in block
         for line in block["lines"] for span in line["spans"]]
# The fixture inherits Scribe's normal #1D1D1F text colour. Its bold change
# remains authored formatting even when screen review decoration is excluded.
assert all(span["color"] == 0x1D1D1F for span in spans)
assert any("Formatted" in span["text"] and span["flags"] & 16 for span in spans)
assert not page.get_images()
assert all(path["type"] == "f" for path in page.get_drawings()), "Review strokes leaked into PDF"
pixmap = pymupdf.Pixmap(str(folder / "ReviewDrawing.png"))
pixels = pixmap.samples
colors = [pixels[i:i + 3] for i in range(0, len(pixels), pixmap.n)]
assert sum(r < 80 and 80 < g < 150 and b < 100 for r, g, b in colors) >= 5, "Missing green insertion marks"
assert sum(r > 120 and g < 100 and b < 100 for r, g, b in colors) >= 5, "Missing red deletion marks"
assert sum(r < 100 and g < 130 and b > 130 for r, g, b in colors) >= 2, "Missing blue formatting marks"
print("Native insertion/deletion/formatting marks are visible; PDF retains vector text and authored formatting without review strokes.")
