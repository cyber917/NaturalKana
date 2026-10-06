#!/usr/bin/env python3
"""Export upstream changes with public identifiers, without changing the local installed app identity."""
from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    public = json.loads((ROOT / 'Config/Brand.json').read_text())
    local_path = ROOT / 'Config/LocalBrand.json'
    local = json.loads(local_path.read_text()) if local_path.exists() else public
    replacements = sorted([(local[k], public[k]) for k in public if k != 'name' and local[k] != public[k]], key=lambda item: -len(item[0]))
    for platform, folder in [('ios', 'azooKey-ios'), ('macos', 'azooKey-macos')]:
        patch = subprocess.check_output(['git', 'diff', '--binary'], cwd=ROOT / 'upstream' / folder).decode()
        for source, destination in replacements:
            patch = patch.replace(source, destination)
        # Personal signing settings belong in a developer's local Xcode configuration.
        patch = re.sub(r'(?m)^(\+\s*(?:DEVELOPMENT_TEAM|DevelopmentTeam)\s*=\s*)[^;]*;', r'\1"";', patch)
        for key in ['signingTeam', 'signingIdentity']:
            if value := local.get(key):
                patch = patch.replace(value, '')
        (ROOT / 'patches' / f'{platform}.patch').write_text(patch)
        print(f'Exported {platform} patch with public identifiers')

if __name__ == '__main__':
    main()
