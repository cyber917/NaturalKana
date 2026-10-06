#!/usr/bin/env python3
"""Check the files Git would publish, without printing sensitive matches."""
from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def main():
    names = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
    private = []
    local = ROOT / 'Config/LocalBrand.json'
    if local.exists():
        data = json.loads(local.read_text())
        public = json.loads((ROOT / 'Config/Brand.json').read_text())
        private = [v for k, v in data.items() if isinstance(v, str) and k != 'name' and v and v != public.get(k)]
        private += data.get('privateTokens', [])
    secrets = re.compile(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')
    paths = re.compile(r'/Users/(?!<|USER/|example/|\$)[A-Za-z0-9_.-]+/')
    issues = []
    checked = 0
    for name in sorted(set(names)):
        p = ROOT / name
        if not name or not p.is_file(): continue
        if name.startswith(('imports/', 'installed-backups/', 'Config/Local')) or p.suffix in ('.p12', '.mobileprovision', '.ipa', '.log'):
            issues.append((name, 'local-only file')); continue
        try: content = p.read_text()
        except UnicodeError: continue
        checked += 1
        if any(token in content for token in private): issues.append((name, 'local identity'))
        if secrets.search(content): issues.append((name, 'possible credential'))
        if paths.search(content): issues.append((name, 'personal home path'))
    for name, reason in issues: print(f'{name}: {reason}')
    print(f'Checked {checked} text files; {len(issues)} findings. Matched values are not printed.')
    raise SystemExit(bool(issues))

if __name__ == '__main__': main()
