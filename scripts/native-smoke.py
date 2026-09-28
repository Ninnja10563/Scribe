#!/usr/bin/env python3
"""Run the real macOS app with a deadline and retain diagnostics on a stalled launch."""
import os
from pathlib import Path
import subprocess
import sys

output = Path(os.environ.get('SCRIBE_SMOKE_OUTPUT', 'build/smoke'))
output.mkdir(parents=True, exist_ok=True)
log_path = output / 'launch.log'
with log_path.open('w') as log:
    process = subprocess.Popen([sys.argv[1], '--smoke-test'], stdout=log, stderr=subprocess.STDOUT)
    try:
        status = process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        print('Native smoke test exceeded 90 seconds; collecting a process sample.', file=sys.stderr)
        try:
            subprocess.run(['/usr/bin/sample', str(process.pid), '3', '-file', str(output / 'process-sample.txt')], timeout=15, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f'Could not sample the app: {error}', file=sys.stderr)
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        status = 1
print(log_path.read_text())
raise SystemExit(status)
