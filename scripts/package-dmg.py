#!/usr/bin/env python3
"""Create local installer ZIP/DMG from an existing verified Vale app; never install it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def command(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f'{Path(str(args[0])).name} failed ({result.returncode}); no apps were installed or launched.')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create(args):
    app = args.app.absolute()
    if (app.is_symlink() or not app.is_dir() or args.verification.is_symlink()
            or args.verification.suffix.lower() != '.json'):
        raise SystemExit('Expected a regular app bundle and verification receipt.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if (not re.fullmatch(r'\d+(?:\.\d+)*', version)
            or not re.fullmatch(r'\d+(?:\.\d+)*', build)
            or info['CFBundleIdentifier'] != 'local.lilt.companion'
            or info['CFBundleExecutable'] != 'Lilt'):
        raise SystemExit('Unexpected setup application identity/version.')
    proof = json.loads(args.verification.read_text())
    if (proof.get('version') != version or proof.get('build') != build
            or proof.get('bundleIdentifier') != info['CFBundleIdentifier']
            or proof.get('appExecutableSHA256') != digest(app / 'Contents/MacOS/Lilt')):
        raise SystemExit('Verification receipt does not describe the exact app executable/version.')
    if proof.get('published') is not False or proof.get('laptopInstalled') is not False:
        raise SystemExit('Setup preparation requires explicit unpublished/uninstalled labels.')
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    output = args.output_dir.absolute()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.vale-setup-', dir=output) as directory:
        temporary = Path(directory)
        setup = temporary / f'Vale-{version}-laptop-setup'
        setup.mkdir()
        command('/usr/bin/ditto', app, setup / 'Vale.app')
        if ((setup / 'Vale.app/Contents/Info.plist').read_bytes() != (app / 'Contents/Info.plist').read_bytes()
                or digest(setup / 'Vale.app/Contents/MacOS/Lilt') != proof['appExecutableSHA256']):
            raise SystemExit('Staged app does not match the verified source.')
        command('/usr/bin/codesign', '--verify', '--deep', '--strict', setup / 'Vale.app')
        shutil.copyfile(ROOT / 'scripts/install.sh', setup / 'install.sh')
        (setup / 'install.sh').chmod(0o755)
        wrapper = setup / 'Install Vale.command'
        wrapper.write_text('#!/bin/zsh\nset -euo pipefail\nvale_setup_dir="${0:A:h}"\n'
                           'export VALE_APP_SOURCE="$vale_setup_dir/Vale.app"\n'
                           '"$vale_setup_dir/install.sh" --replace\n')
        wrapper.chmod(0o755)
        command('/bin/zsh', '-n', setup / 'install.sh')
        command('/bin/zsh', '-n', wrapper)
        (setup / 'verification.json').write_text(json.dumps(proof, indent=2, sort_keys=True) + '\n')
        signature = proof.get('signature', {}).get('kind', 'unverified')
        web = proof.get('knownFailureAcknowledged') == 'explicitWebSearchUsesRealTool'
        readme = f'''Vale {version} (build {build}) — configured bootstrap setup

Open “Install Vale.command” on your laptop. It stages and verifies this app,
requests normal quit of matching Vale/Lilt copies, installs ~/Applications/Vale.app,
and verifies its launch before moving superseded app bundles to Trash. The previous
app is retained for rollback until launch succeeds. Chats, deliberate attachments,
settings, credentials and macOS privacy/security permissions stay in their existing
locations. The installer requires no Swift, Python, lipo or developer tools.

Respond personally to normal macOS security confirmations. This installer does
not remove quarantine, change security settings, force-quit an app or use sudo.
Signature: {signature}; notarization is not verified. This package is unpublished
local preparation and has not been installed or tested on your laptop. Intel and
Apple Silicon slices are present; target-laptop/Apple Silicon runtime remains
unverified here.

This configured bootstrap starts signed automatic update checks while Vale is
open, respecting saved preferences. Automatic downloads normally install when
Vale quits; Settings offers both controls and a manual check. Older builds with
no feed/public key need this one-time manual replacement. Preparation of a pinned
feed/key does not mean the production HTTPS feed has been published or verified;
until that delivery step completes a check can report an unavailable feed.

'''
        if web:
            readme += '''Known limitation: the genuine Web integration assertion failed in the
tested CLI/runtime with execution tools disabled. Its false result remains in
verification.json. Web search is not accepted for this candidate. No execution
permission or paid fallback was enabled to manufacture a pass. The laptop's
actual CLI/runtime remains unverified.

'''
        readme += '''See verification.json for exact unchanged assertion maps, SDK fixture
boundaries and remaining work. Repeated/native/fixture counts overlap and are not
independent end-to-end journeys. This setup does not establish published updates,
notarized distribution, real microphone/screen hardware or laptop acceptance.
'''
        (setup / 'README.txt').write_text(readme)
        setup_zip = temporary / f'Vale-{version}-laptop-setup.zip'
        setup_dmg = temporary / f'Vale-{version}-laptop-setup.dmg'
        command('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', setup, setup_zip)
        command('/usr/bin/unzip', '-t', setup_zip)
        command('/usr/bin/hdiutil', 'create', '-srcfolder', setup, '-volname', f'Vale {version}',
                '-format', 'UDZO', setup_dmg)
        command('/usr/bin/hdiutil', 'verify', setup_dmg)
        os.replace(setup_zip, output / setup_zip.name)
        os.replace(setup_dmg, output / setup_dmg.name)
    print(json.dumps({'setupZIP': setup_zip.name, 'setupDMG': setup_dmg.name,
                      'installed': False, 'published': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--app', type=Path, default=ROOT / 'dist/Vale.app')
    parser.add_argument('--verification', type=Path)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if args.plan:
        print(json.dumps({'planOnly': True, 'contents': ['Vale.app', 'install.sh', 'Install Vale.command', 'README.txt', 'verification.json'],
                          'actions': ['copy', 'signature verification', 'shell syntax', 'ZIP creation', 'DMG creation/verification'],
                          'installerExecuted': False, 'published': False}, indent=2))
    elif args.verification is None:
        parser.error('--verification is required outside --plan')
    else:
        create(args)


if __name__ == '__main__':
    main()
