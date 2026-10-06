#!/usr/bin/env python3
"""Bundle the already-built macOS preview. Pass the Swift build products directory."""
from pathlib import Path
import argparse, json, plistlib, shutil, subprocess
parser=argparse.ArgumentParser();parser.add_argument('products',type=Path);args=parser.parse_args()
root=Path(__file__).resolve().parents[1];brand=json.loads((root/'Config/Brand.json').read_text());app=root/'NaturalKanaPreview.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True);(app/'Contents/Resources').mkdir(exist_ok=True)
temporary=app/'Contents/MacOS/NaturalKanaPreview.new'
shutil.copy2(args.products/'NaturalKanaPreview',temporary)
temporary.replace(app/'Contents/MacOS/NaturalKanaPreview')
shutil.copytree(args.products/'NaturalSuggestCore_NaturalSuggestCore.bundle',app/'Contents/Resources/NaturalSuggestCore_NaturalSuggestCore.bundle',dirs_exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='NaturalKanaPreview',CFBundleIdentifier=brand['bundlePrefix']+'.preview',CFBundleName=brand['name']+' Preview',CFBundleDisplayName=brand['name']+' Preview',CFBundlePackageType='APPL',CFBundleShortVersionString='0.1',CFBundleVersion='1',LSMinimumSystemVersion='13.0',NSHighResolutionCapable=True)))
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
print(app)
