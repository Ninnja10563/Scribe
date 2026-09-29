"""Compare sampled first/middle/last pages after deferred and fresh native layout."""
import json
import sys
from pathlib import Path

import pymupdf

folder = Path(sys.argv[1])
with pymupdf.open(folder / 'BudgetedLayout.pdf') as budgeted, pymupdf.open(folder / 'SynchronousLayout.pdf') as fresh:
    assert len(budgeted) == len(fresh) == 3, 'Expected first, middle and last sampled pages'
    measurements = []
    for index, (actual, expected) in enumerate(zip(budgeted, fresh)):
        assert actual.rect == expected.rect, f'Sample {index}: page dimensions differ'
        words = actual.get_text('words')
        assert words == expected.get_text('words'), f'Sample {index}: word text or positions differ'
        a = actual.get_pixmap(matrix=pymupdf.Matrix(2, 2))
        b = expected.get_pixmap(matrix=pymupdf.Matrix(2, 2))
        assert (a.width, a.height, a.n) == (b.width, b.height, b.n), f'Sample {index}: raster dimensions differ'
        assert a.samples == b.samples, f'Sample {index}: rendered pixels differ'
        measurements.append({'sample': index + 1, 'words': len(words), 'pixelsEqual': True})
    print(json.dumps(measurements, indent=2))
print('Budgeted first/middle/last PDF samples exactly match fresh layout words, positions and 2x pixels.')
