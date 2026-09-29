#!/usr/bin/env python3
"""Validate review decisions and vector markup in actual body/note PDFs."""
import sys
from pathlib import Path
import pymupdf

folder = Path(sys.argv[1])
for prefix in ("ReviewOutput", "ReviewEndnote"):
    stroke_counts = {}
    for mode in ("Marked", "Accepted", "Rejected"):
        document = pymupdf.open(folder / f"{prefix}{mode}.pdf")
        expected_pages = 1 if prefix == "ReviewOutput" else 2
        assert len(document) == expected_pages
        text = "\n".join(page.get_text() for page in document)
        spans = [span for page in document for block in page.get_text("dict")["blocks"] if "lines" in block
                 for line in block["lines"] for span in line["spans"]]
        assert all(not page.get_images() for page in document)
        assert sum(len(page.get_links()) for page in document) >= 2, "Missing note/reference links"
        stroke_counts[mode] = sum("s" in path["type"] for page in document for path in page.get_drawings())
        if mode == "Marked":
            assert "Old New stable" in text and "Note oldNote new" in text
            for word, color in (("Old", 0xAD2929), ("New", 0x14663B), ("Note old", 0xAD2929), ("Note new", 0x14663B)):
                assert any(word in span["text"] and span["color"] == color for span in spans), (prefix, word)
        else:
            expected, removed = ("New", "Old") if mode == "Accepted" else ("Old", "New")
            assert f"{expected} stable" in text and f"Note {expected.lower()}" in text
            assert removed not in text and f"Note {removed.lower()}" not in text
            assert all(span["color"] in (0, 0x1D1D1F) for span in spans)
    assert stroke_counts["Accepted"] == stroke_counts["Rejected"]
    assert stroke_counts["Marked"] >= stroke_counts["Accepted"] + 4
print("Marked, accepted and rejected PDF output verified for body text, footnotes and endnotes, including vector marks and note links.")
