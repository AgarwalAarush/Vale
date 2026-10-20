#!/usr/bin/env python3
"""Explicitly gated isolated Sparkle experiment. Default command only prints plan."""
import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import tempfile
import threading
import time
import uuid

DEFAULT_REPO = Path(__file__).resolve().parent.parent
HERE = DEFAULT_REPO / 'Tests' / 'SparkleUpgrade'


def command(args, *, allow_failure=False, env=None):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env)
    if result.returncode and not allow_failure:
        # Commands never receive private key contents as arguments. Do not print tool stderr.
        raise RuntimeError(f'{Path(str(args[0])).name} failed with exit {result.returncode}; inspect the local fixture')
    return result


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_root(path):
    root = Path(path).resolve(strict=True)
    if root.parent != Path('/private/tmp') or not root.name.startswith('vale-sparkle-fixture.'):
        raise RuntimeError('Refusing a root outside the dedicated temporary fixture directory')
    if root.is_symlink() or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
        raise RuntimeError('Fixture root must be owned by this user and mode 0700')
    return root


def prepare(args):
    if not args.authorize_ephemeral_keys:
        raise RuntimeError('Preparation requires --authorize-ephemeral-keys after coordinator review')
    sdk = args.repo.resolve() / '.build/artifacts/sparkle/Sparkle'
    framework = sdk / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    signer = sdk / 'bin/sign_update'
    for required in (framework, signer, HERE / 'FixtureApp.m', HERE / 'make-test-keys.swift'):
        if not required.exists():
            raise RuntimeError(f'Missing required file: {required}')
    os.umask(0o077)
    root = checked_root(tempfile.mkdtemp(prefix='vale-sparkle-fixture.', dir='/private/tmp'))
    server_dir = root / 'server'
    server_dir.mkdir()
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    bundle_id = 'local.vale.sparklefixture.' + uuid.uuid4().hex
    feed_url = f'http://127.0.0.1:{port}/appcast.xml'
    archive_url = f'http://127.0.0.1:{port}/Fixture.zip'
    module_cache = root / 'module-cache'
    module_cache.mkdir()
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(module_cache), SWIFT_MODULECACHE_PATH=str(module_cache))
    command(['/usr/bin/swift', '-module-cache-path', module_cache, HERE / 'make-test-keys.swift',
             '--generate-ephemeral-files', root], env=env)
    seed = root / 'test-seed.base64'
    if seed.stat().st_mode & 0o077:
        raise RuntimeError('Private fixture seed permissions are not 0600')
    public_key = (root / 'test-public.base64').read_text().strip()
    apps = {}
    for build, folder in ((1, 'installed'), (2, 'payload')):
        app = root / folder / 'Fixture.app'
        contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Frameworks').mkdir()
        command(['/usr/bin/ditto', framework, contents / 'Frameworks/Sparkle.framework'])
        info = {
            'CFBundleIdentifier': bundle_id,
            'CFBundleExecutable': 'Fixture',
            'CFBundleName': 'Sparkle Fixture',
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': str(build),
            'CFBundleShortVersionString': f'0.0.{build}',
            'LSMinimumSystemVersion': '14.0',
            'LSUIElement': True,
            'FixtureRoot': str(root),
            'FixtureMode': args.mode,
            'SUFeedURL': feed_url,
            'SUPublicEDKey': public_key,
            'SUEnableAutomaticChecks': True,
            'SUAutomaticallyUpdate': True,
            'SUAllowsAutomaticUpdates': True,
            'SURequireSignedFeed': True,
            'SUVerifyUpdateBeforeExtraction': True,
            'SUSignedFeedFailureExpirationInterval': 0,
            'SUSendProfileInfo': False,
            # Explicitly fixture-only. No production policy or system setting is modified.
            'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True, 'NSAllowsArbitraryLoads': True},
        }
        with (contents / 'Info.plist').open('wb') as target:
            plistlib.dump(info, target)
        command(['/usr/bin/clang', '-fobjc-arc', '-fmodules', f'-fmodules-cache-path={module_cache}',
                 '-mmacosx-version-min=14.0', f'-DFIXTURE_BUILD={build}', '-F', framework.parent,
                 '-framework', 'Cocoa', '-framework', 'Sparkle',
                 '-Wl,-rpath,@executable_path/../Frameworks', HERE / 'FixtureApp.m',
                 '-o', contents / 'MacOS/Fixture'], env=env)
        # Sign only our host. Retain the bundled SDK's nested signatures and symlinks.
        command(['/usr/bin/codesign', '--force', '--sign', '-', app])
        command(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
        apps[build] = app
    archive = server_dir / 'Fixture.zip'
    command(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', apps[2], archive])
    signature = command([signer, '--ed-key-file', seed, '-p', archive]).stdout.strip()
    crypto = {'validArchive': command([signer, '--verify', '--ed-key-file', seed, archive, signature], allow_failure=True).returncode == 0}
    original_archive_hash = digest(archive)
    if args.case == 'archive-tamper':
        # Keep a well-formed ZIP; the signed feed states actual length but retains the original signature.
        with archive.open('ab') as target:
            target.write(b'fixture-tamper')
        crypto['tamperedArchiveRejected'] = command([signer, '--verify', '--ed-key-file', seed, archive, signature], allow_failure=True).returncode != 0
    feed = server_dir / 'appcast.xml'
    feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<title>Fixture update</title><item><title>Fixture 2</title>
<sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<enclosure url="{archive_url}" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
</item></channel></rss>
''')
    command([signer, '--ed-key-file', seed, '--disable-signing-warning', feed])
    crypto['validFeed'] = command([signer, '--verify', '--ed-key-file', seed, feed], allow_failure=True).returncode == 0
    if args.case == 'feed-tamper':
        data = feed.read_bytes()
        if b'<title>Fixture update</title>' not in data:
            raise RuntimeError('Expected signed feed fixture marker missing')
        feed.write_bytes(data.replace(b'<title>Fixture update</title>', b'<title>Fixture altered</title>', 1))
        crypto['tamperedFeedRejected'] = command([signer, '--verify', '--ed-key-file', seed, feed], allow_failure=True).returncode != 0
    if not all(crypto.values()):
        raise RuntimeError('Signing/verifier precondition failed; no fixture will be launched')
    metadata = {
        'case': args.case, 'mode': args.mode, 'bundleID': bundle_id,
        'port': port, 'app': str(apps[1]),
        'oldExecutableSHA256': digest(apps[1] / 'Contents/MacOS/Fixture'),
        'newExecutableSHA256': digest(apps[2] / 'Contents/MacOS/Fixture'),
        'validArchiveSHA256': original_archive_hash,
        'servedArchiveSHA256': digest(archive), 'servedFeedSHA256': digest(feed),
        'cryptoOnly': crypto, 'sdkVersion': '2.10.0',
    }
    save(root / 'prepared.json', metadata)
    print(json.dumps({'preparedRoot': str(root), 'cryptoOnly': crypto, 'appLaunched': False}, indent=2))


def run(args):
    if not args.authorize_fixture_gui_cache:
        raise RuntimeError('Running requires --authorize-fixture-gui-cache after coordinator review')
    root = checked_root(args.run_root)
    metadata = json.loads((root / 'prepared.json').read_text())
    app = Path(metadata['app'])
    if app.resolve().parent != root / 'installed' or app.name != 'Fixture.app':
        raise RuntimeError('Refusing unexpected fixture app path')
    if (root / 'run-started.json').exists():
        raise RuntimeError('Refusing to reuse a fixture root/defaults domain')
    if not metadata['bundleID'].startswith('local.vale.sparklefixture.'):
        raise RuntimeError('Refusing unexpected bundle ID')
    requests = []
    class Handler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_GET(self):
            requests.append(self.path.split('?', 1)[0])
            save(root / 'http-requests.json', requests)
            super().do_GET()
    handler = functools.partial(Handler, directory=str(root / 'server'))
    server = http.server.ThreadingHTTPServer(('127.0.0.1', metadata['port']), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    save(root / 'run-started.json', {'bundleID': metadata['bundleID'], 'time': time.time()})
    executable = app / 'Contents/MacOS/Fixture'
    receipts = []
    runner_relaunch = False
    try:
        command(['/usr/bin/open', '-n', app])
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            receipts = []
            for file in root.glob('*.json'):
                if file.name in ('prepared.json', 'run-started.json', 'http-requests.json', 'result.json'):
                    continue
                try:
                    value = json.loads(file.read_text())
                    if isinstance(value, dict) and 'event' in value:
                        receipts.append(value)
                except (ValueError, OSError):
                    pass
            events = {r['event'] for r in receipts}
            actual_hash = digest(executable)
            if metadata['case'] == 'valid' and actual_hash == metadata['newExecutableSHA256']:
                if metadata['mode'] == 'quit' and not runner_relaunch:
                    # Separate evidence from Sparkle's relaunch: ordinary quit installs, runner then launches exact updated fixture.
                    command(['/usr/bin/open', '-n', app])
                    runner_relaunch = True
                if 'new-did-launch' in events and 'user-data-restored' in events:
                    break
            if metadata['case'] != 'valid' and 'sdk-abort' in events:
                break
            time.sleep(0.2)
        events = {r['event'] for r in receipts}
        actual_hash = digest(executable)
        appcast_fetched = '/appcast.xml' in requests
        archive_fetched = '/Fixture.zip' in requests
        crypto_rejections = []
        for receipt in receipts:
            chain = receipt.get('errorChain', [])
            codes = {e.get('code') for e in chain if e.get('domain') == 'SUSparkleErrorDomain'}
            if receipt['event'] == 'sdk-abort' and receipt.get('signatureRelated') and codes.intersection({1000, 3001, 3002}):
                crypto_rejections.append(chain)
        checks = {'feedFetched': appcast_fetched}
        if metadata['case'] == 'valid':
            startup = [r for r in receipts if r['event'] == 'updater-started']
            checks.update({
                'automaticDefaultsObserved': bool(startup) and all(r.get('automaticChecks') and r.get('automaticDownloads') for r in startup),
                'archiveFetched': archive_fetched,
                'readyOnQuit': 'ready-on-quit' in events,
                'newExecutableInstalled': actual_hash == metadata['newExecutableSHA256'],
                'newCompiledBinaryLaunched': any(r['event'] == 'new-did-launch' and r.get('compiledBuild') == 2 for r in receipts),
                'generatedDataPreserved': any(r['event'] == 'user-data-restored' and all(r.get(key) is True for key in ('draftPreserved','notePreserved','attachmentPreserved','preferencePreserved')) for r in receipts),
            })
        else:
            checks.update({
                'SDKCryptographicRejection': bool(crypto_rejections),
                'oldExecutablePreserved': actual_hash == metadata['oldExecutableSHA256'],
                'noInstallReady': 'ready-on-quit' not in events,
                'expectedArchiveFetch': archive_fetched == (metadata['case'] == 'archive-tamper'),
            })
        result = {
            'case': metadata['case'], 'mode': metadata['mode'], 'checks': checks,
            'passed': all(checks.values()), 'runnerRelaunchAfterNormalQuit': runner_relaunch,
            'errorChains': crypto_rejections, 'installedExecutableSHA256': actual_hash,
            'boundary': 'Real SDK with loopback HTTP/ad-hoc fixture; not production HTTPS, notarization, live publication, or user-laptop acceptance.',
        }
        save(root / 'result.json', result)
        print(json.dumps(result, indent=2))
        if not result['passed']:
            raise RuntimeError('Fixture acceptance failed; inspect local receipts; no host application was terminated')
    finally:
        server.shutdown()
        server.server_close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action')
    sub.add_parser('plan')
    prepare_parser = sub.add_parser('prepare')
    prepare_parser.add_argument('--authorize-ephemeral-keys', action='store_true')
    prepare_parser.add_argument('--repo', type=Path, default=DEFAULT_REPO)
    prepare_parser.add_argument('--case', choices=('valid', 'feed-tamper', 'archive-tamper'), default='valid')
    prepare_parser.add_argument('--mode', choices=('quit', 'relaunch'), default='quit')
    run_parser = sub.add_parser('run')
    run_parser.add_argument('--authorize-fixture-gui-cache', action='store_true')
    run_parser.add_argument('run_root', type=Path)
    args = parser.parse_args()
    if args.action in (None, 'plan'):
        print((HERE / 'README.md').read_text())
    elif args.action == 'prepare':
        prepare(args)
    else:
        run(args)


if __name__ == '__main__':
    main()
