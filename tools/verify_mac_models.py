#!/usr/bin/env python3
"""Reject incomplete downloads and LFS pointers before packaging a runnable IME."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
valid = True
for item in json.loads((root / 'Config/MacModels.json').read_text()):
    path = root / 'upstream/azooKey-macos' / item['path']
    if not path.is_file() or path.stat().st_size != item['size']:
        print('Missing or incomplete:', item['path'])
        valid = False
        continue
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != item['sha256']:
        print('Checksum mismatch:', item['path'])
        valid = False
    else:
        print('Verified:', item['path'])
raise SystemExit(0 if valid else 1)
