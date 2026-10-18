#!/usr/bin/env python3
"""Read-only RSS samples for local G1 use; output stays private."""
import datetime, subprocess, time
from pathlib import Path
root = Path(__file__).resolve().parent.parent
with (root / 'Private/host-rss.tsv').open('a') as out:
    for _ in range(120):
        found = subprocess.run(['pgrep', '-x', 'legacyScreenSaver'], capture_output=True, text=True)
        for pid in found.stdout.split():
            result = subprocess.run(['ps', '-o', 'pid=,rss=,etime=', '-p', pid], capture_output=True, text=True)
            out.write(datetime.datetime.now().isoformat(timespec='seconds')+'\t'+result.stdout.strip()+'\n')
        out.flush()
        time.sleep(1)
