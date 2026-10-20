#!/usr/bin/env python3
"""Check the real Vale updater in an isolated, reidentified copy of a candidate."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import time
import uuid


def command(*args):
    subprocess.run([str(value) for value in args], check=True, capture_output=True)


def prepare(app):
    app = app.resolve(strict=True)
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'local.lilt.companion' or not info.get('SURequireSignedFeed') or not info.get('SUVerifyUpdateBeforeExtraction') or info.get('SUSignedFeedFailureExpirationInterval') != 0:
        raise ValueError('Expected the strictly configured Vale candidate')
    if info.get('SUFeedURL') != 'https://github.com/AgarwalAarush/Vale/releases/latest/download/appcast.xml':
        raise ValueError('Expected the production feed address')
    os.umask(0o077)
    root = Path(tempfile.mkdtemp(prefix='vale-release-check.', dir='/private/tmp')).resolve()
    identifier = 'local.vale.releasecheck.' + uuid.uuid4().hex
    target = root / 'Vale.app'
    command('/usr/bin/ditto', app, target)
    info['CFBundleIdentifier'] = identifier
    # A suite equal to the main bundle ID is invalid on macOS. The unique
    # main bundle ID already isolates standard defaults used by Sparkle.
    info.pop('SUDefaultsDomain', None)
    (target / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    command('/usr/bin/codesign', '--force', '--sign', '-', '--identifier', identifier, target)
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', target)
    (root / 'request.json').write_text(json.dumps({'bundleID': identifier, 'app': str(target)}) + '\n')
    print(json.dumps({'root': str(root), 'bundleID': identifier, 'appLaunched': False}, indent=2))


def run(path):
    root = path.resolve(strict=True)
    if root.parent != Path('/private/tmp') or not root.name.startswith('vale-release-check.') or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
        raise ValueError('Expected a user-owned private disposable release-check directory')
    request = json.loads((root / 'request.json').read_text())
    app = root / 'Vale.app'
    if request['app'] != str(app) or not request['bundleID'].startswith('local.vale.releasecheck.'):
        raise ValueError('Unexpected fixture identity')
    evidence = root / 'evidence'
    if evidence.exists():
        raise ValueError('Refusing to reuse a release-check preference domain')
    evidence.mkdir()
    source_head = os.environ.get('VALE_EVIDENCE_HEAD')
    if source_head is not None and not re.fullmatch(r'[0-9a-f]{40}', source_head):
        raise ValueError('Expected a full source revision for native evidence')
    launch_environment = ['--env', 'VALE_EVIDENCE_HEAD=' + source_head] if source_head else []
    for phase, options in [('preferences-off', ['--preferences-off']), ('production-feed', [])]:
        receipt = evidence / (phase + '.json')
        command('/usr/bin/open', '-n', *launch_environment, app, '--args', '--verify-release-feed', *options, evidence)
        deadline = time.monotonic() + 110
        while not receipt.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        if not receipt.exists():
            raise RuntimeError('No isolated app receipt before the deadline; no app was force-quit')
        result = json.loads(receipt.read_text())
        print(json.dumps(result, indent=2))
        termination = subprocess.run(
            ['/usr/bin/osascript', '-l', 'JavaScript', '-', request['bundleID']],
            input="""ObjC.import('AppKit'); ObjC.import('Foundation');
function run(argv) {
    if (!argv[0].startsWith('local.vale.releasecheck.')) throw new Error('Unexpected identity');
    var deadline = Date.now() + 15000;
    while (Date.now() < deadline) {
        var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0]);
        if (Number(apps.count) === 0) return 'stopped';
        $.NSThread.sleepForTimeInterval(0.1);
    }
    throw new Error('The isolated app has not terminated normally.');
}
""", text=True, capture_output=True, timeout=20)
        if termination.returncode or termination.stdout.strip() != 'stopped':
            raise RuntimeError('The isolated app has not terminated normally; no app was force-quit')
        if not result['passed']:
            raise RuntimeError('Real release-feed check did not pass; inspect the recorded receipt')
        if phase == 'preferences-off':
            persisted = {}
            for key in ('SUEnableAutomaticChecks', 'SUAutomaticallyUpdate'):
                value = subprocess.run(['/usr/bin/defaults', 'read', request['bundleID'], key],
                                       text=True, capture_output=True, timeout=10)
                persisted[key] = value.returncode == 0 and value.stdout.strip() == '0'
            (evidence / 'cross-process-preferences.json').write_text(json.dumps(persisted, indent=2) + '\n')
            if not all(persisted.values()):
                raise RuntimeError('Saved updater choices did not persist across normal exit')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest='action', required=True)
    actions.add_parser('prepare').add_argument('app', type=Path)
    actions.add_parser('run').add_argument('root', type=Path)
    args = parser.parse_args()
    if args.action == 'prepare':
        prepare(args.app)
    else:
        run(args.root)


if __name__ == '__main__':
    main()
