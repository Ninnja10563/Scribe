#!/usr/bin/env python3
"""Check output from actual native note-dialog Apply, not a synthetic fixture."""
import json
import sys
from pathlib import Path
import pymupdf

folder = Path(sys.argv[1])
source = json.loads((folder / "TrackedNoteDialog.scribe").read_text())
runs = source["notes"][0]["paragraphs"][0]["runs"]
assert "".join(run["text"] for run in runs) == "Citation added"
assert any(run["text"] == " added" and run.get("review", {}).get("insertion") for run in runs)
for mode in ("Marked", "Accepted", "Rejected"):
    with pymupdf.open(folder / f"TrackedNoteDialog-{mode}.pdf") as document:
        assert len(document) == 1
        page = document[0]
        text = page.get_text()
        assert "Citation" in text
        assert ("added" in text) == (mode != "Rejected")
        assert not page.get_images(), "Note text should remain vector text"
        assert len(page.get_links()) >= 2, "Note and reference must remain linked"
        spans = [span for block in page.get_text("dict")["blocks"] if "lines" in block
                 for line in block["lines"] for span in line["spans"]]
        if mode == "Marked":
            assert any("added" in span["text"] and span["color"] == 0x14663B for span in spans)
        else:
            assert all(span["color"] in (0, 0x1D1D1F) for span in spans)
print("Native note-dialog changes persist in the native file and marked/accepted/rejected vector PDFs with note links.")
