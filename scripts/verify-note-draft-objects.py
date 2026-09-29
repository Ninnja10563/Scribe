#!/usr/bin/env python3
"""Verify existing note objects fit the adaptive draft without resampling geometry."""
import sys
from pathlib import Path
import pymupdf

folder = Path(sys.argv[1])
with pymupdf.open(folder / "NoteDraftImage.pdf") as pdf:
    assert len(pdf) == 1
    page = pdf[0]
    images = page.get_images()
    assert len(images) == 1
    bounds = page.get_image_rects(images[0][0])
    assert len(bounds) == 1
    assert abs(bounds[0].width - 420) < 0.01 and abs(bounds[0].height - 620) < 0.01
    assert page.rect.contains(bounds[0])
with pymupdf.open(folder / "NoteDraftEquation.pdf") as pdf:
    assert len(pdf) == 1
    page = pdf[0]
    assert not page.get_images(), "Equation must remain vector output"
    assert page.get_text().count("𝑥") >= 2
    spans = [span for block in page.get_text("dict")["blocks"] if "lines" in block
             for line in block["lines"] for span in line["spans"]]
    assert spans and all(page.rect.contains(pymupdf.Rect(span["bbox"])) for span in spans)
    assert all(page.rect.contains(path["rect"]) for path in page.get_drawings())
print("Note-draft image preserves 420×620-point geometry; equation stays vector; object bounds fit their pages.")
