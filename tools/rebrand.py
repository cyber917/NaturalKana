#!/usr/bin/env python3
"""Apply Config/Brand.json identities to generated source; preserve target/module filenames."""
from pathlib import Path
import json, re, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
new=json.loads((ROOT/'Config/Brand.json').read_text()); stamp=ROOT/'Config/GeneratedBrand.json';old=json.loads(stamp.read_text())
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9 ]{1,40}',new['name']):raise SystemExit('Use a plain ASCII display name for this generator')
for field in ['bundlePrefix','iosAppGroup','macAppGroup','macBundleIdentifier']:
 if not re.fullmatch(r'[A-Za-z0-9.-]+',new[field]):raise SystemExit('Invalid bundle/group identifier')
replacements=sorted([(old[k],new[k]) for k in new if k!='name' and new[k]!=old[k]],key=lambda x:-len(x[0]))
for base in [ROOT/'upstream',ROOT/'NaturalSuggestCore/Sources']:
 for path in base.rglob('*'):
  if not path.is_file() or '.git' in path.parts or path.suffix not in ['.swift','.plist','.pbxproj','.entitlements','.strings','.xcconfig','.sh']:continue
  try:text=path.read_text()
  except UnicodeError:continue
  before=text
  for a,b in replacements:text=text.replace(a,b)
  if old['name']!=new['name']:
   if path.suffix=='.swift':text=re.sub(r'"[^"\n]*"',lambda m:m[0].replace(old['name'],new['name']),text)
   else:text=text.replace(old['name'],new['name'])
  if text!=before:path.write_text(text)
subprocess.run([sys.executable, str(ROOT/'tools/export_patches.py')], check=True)
stamp.write_text(json.dumps(new,indent=2)+'\n')
print('Generated identities and patches updated. Rebuild, re-sign, and audit localized assets before distribution.')
