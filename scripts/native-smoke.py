#!/usr/bin/env python3
"""Run the real macOS app with a deadline and retain diagnostics on a stalled launch."""
import os
from pathlib import Path
import subprocess
import sys

output = Path(os.environ.get('SCRIBE_SMOKE_OUTPUT', 'build/smoke'))
output.mkdir(parents=True, exist_ok=True)
log_path = output / 'launch.log'
launch_services = '--launch-services' in sys.argv
report = output.resolve() / 'startup-report.txt'
if launch_services:
    report.unlink(missing_ok=True)
    app = Path(sys.argv[1]).resolve().parents[2]
    command = ['/usr/bin/open', '-n', '-W', '--stdout', str(output.resolve() / 'app-stdout.log'), '--stderr', str(output.resolve() / 'app-stderr.log'), str(app), '--args', '--startup-smoke-test', '--startup-report', str(report)]
else:
    command = [sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '--smoke-test']
with log_path.open('w') as log:
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    try:
        status = process.wait(timeout=90)
    except subprocess.TimeoutExpired:
        print('Native smoke test exceeded 90 seconds; collecting a process sample.', file=sys.stderr)
        try:
            subprocess.run(['/usr/bin/sample', str(process.pid), '3', '-file', str(output / 'process-sample.txt')], timeout=15, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            print(f'Could not sample the app: {error}', file=sys.stderr)
        if launch_services:
            found = subprocess.run(['/usr/bin/pgrep', '-x', 'Scribe'], capture_output=True, text=True)
            for pid in found.stdout.split():
                subprocess.run(['/usr/bin/sample', pid, '2', '-file', str(output / ('scribe-' + pid + '-sample.txt'))], timeout=15, check=False)
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        status = 1
if launch_services and (not report.exists() or 'Dock reopen passed' not in report.read_text()):
    print('Launch Services did not produce a successful startup report.', file=sys.stderr)
    for path in output.glob('app-*.log'):
        print(path.name + ':\n' + path.read_text(errors='replace'))
    status = 1
print(log_path.read_text())
raise SystemExit(status)
