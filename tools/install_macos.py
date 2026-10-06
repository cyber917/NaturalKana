#!/usr/bin/env python3
"""Install the verified local build for this user, without changing the active input source."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--registrar', type=Path, required=True)
args = parser.parse_args()
source = args.app.resolve()
brand_file = root / 'Config/LocalBrand.json'
if not brand_file.exists():
    brand_file = root / 'Config/Brand.json'
identifier = json.loads(brand_file.read_text())['macBundleIdentifier']
legacy_identifier = 'org.naturalkana.mac'
service = identifier + '.ConverterServer'
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != identifier:
    raise SystemExit('Unexpected app identity; nothing installed.')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
for item in json.loads((root / 'Config/MacModels.json').read_text()):
    # Xcode copies these file references directly into Contents/Resources.
    resource = Path(item['path']).name
    model = source / 'Contents/Resources' / resource
    if not model.is_file() or model.stat().st_size != item['size']:
        raise SystemExit('Bundled model missing/incomplete: ' + str(resource))
    digest = hashlib.sha256()
    with model.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != item['sha256']:
        raise SystemExit('Bundled model checksum mismatch: ' + str(resource))

library = Path.home() / 'Library'
destination = library / 'Input Methods/NaturalKana.app'
destination.parent.mkdir(parents=True, exist_ok=True)
staging = destination.with_name('NaturalKana.installing.app')
if staging.exists():
    raise SystemExit('A staging app already exists; inspect it before retrying: ' + str(staging))
subprocess.run(['ditto', str(source), str(staging)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(staging)], check=True)
if destination.exists():
    old = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
    if old.get('CFBundleIdentifier') not in (identifier, legacy_identifier):
        raise SystemExit('Existing destination is another app; preserved.')
    backup = root / 'installed-backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup.mkdir(parents=True)
    shutil.move(str(destination), str(backup / destination.name))
    if old.get('CFBundleIdentifier') == legacy_identifier:
        legacy_agent = library / 'LaunchAgents' / (legacy_identifier + '.ConverterServer.plist')
        if legacy_agent.exists():
            subprocess.run(['launchctl', 'bootout', 'gui/' + str(os.getuid()), str(legacy_agent)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            shutil.move(str(legacy_agent), str(backup / legacy_agent.name))
staging.rename(destination)

agent = library / 'LaunchAgents' / (service + '.plist')
agent.parent.mkdir(parents=True, exist_ok=True)
helper = destination / 'Contents/Helpers/ConverterServer/ConverterServer'
payload = dict(Label=service, ProgramArguments=[str(helper)], MachServices={service: True},
               KeepAlive=True, RunAtLoad=True, StandardOutPath='/dev/null', StandardErrorPath='/dev/null')
temporary = agent.with_suffix('.plist.new')
temporary.write_bytes(plistlib.dumps(payload))
temporary.replace(agent)
domain = 'gui/' + str(os.getuid())
subprocess.run(['launchctl', 'bootout', domain, str(agent)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['launchctl', 'bootstrap', domain, str(agent)], check=True)
subprocess.run(['launchctl', 'kickstart', domain + '/' + service], check=True)
registration = subprocess.run([str(args.registrar.resolve()), '--register', str(destination)])
print('Installed:', destination)
print('Active input source was not changed.')
if registration.returncode == 3:
    print('Manual setup required: add NaturalKana in System Settings > Keyboard > Text Input > Edit > +.')
elif registration.returncode:
    raise SystemExit(registration.returncode)
