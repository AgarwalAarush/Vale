#!/usr/bin/env python3
"""Bounded production-HTTPS Sparkle upgrade of a private published-Vale copy.

Default/plan is read-only. `prepare --old-app APP --expected-app APP --sdk SDK`
copies, compiles and ad-hoc signs private fixture bundles, without launching or
contacting the network. --expected-archive ZIP may replace --expected-app.
Optional --output-private must be a new /private/tmp/vale-published-upgrade.*
directory. `run ROOT --authorize-gui-and-sdk-cache` uses the actual SDK/live
signed production feed. No private signing keys or installed Vale data are read.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import re
import subprocess
import tempfile
import time
import urllib.parse
import uuid
import zipfile

FEED = 'https://github.com/AgarwalAarush/Vale/releases/latest/download/appcast.xml'
PUBLIC_KEY = 'LIo57815YwKGJzwijcc6uut6Q4H5nShI95d99T6O4Z8='
BUNDLE_ID = 'local.lilt.companion'
HERE = Path(__file__).resolve().parent


def command(args, timeout=60, env=None):
    result = subprocess.run([str(a) for a in args], capture_output=True, timeout=timeout, env=env)
    if result.returncode:
        raise RuntimeError(f'{Path(str(args[0])).name} failed with exit {result.returncode}; no private tool output copied')
    return result.stdout


def digest(path):
    hasher = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            hasher.update(block)
    return hasher.hexdigest()


def executable_code_digest(path):
    """Hash native instruction bytes in each architecture, excluding signatures.

    Ad-hoc re-signing changes Mach-O signature/load-command bytes. otool's actual
    __TEXT,__text section dump stays identical in a controlled metadata clone.
    This is instruction-section equivalence, not whole-file equivalence.
    """
    output = command(['/usr/bin/otool', '-s', '__TEXT', '__text', path])
    rows = [line for line in output.splitlines() if re.match(rb'^[0-9a-fA-F]{8,16}\s+[0-9a-fA-F]', line)]
    if not rows:
        raise ValueError('No native instruction sections found')
    return hashlib.sha256(b'\n'.join(rows)).hexdigest()


def optional_digest(path):
    try:
        return digest(path)
    except FileNotFoundError:
        return None


def save(path, value):
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with temporary.open('x') as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write('\n')
    temporary.chmod(0o600)
    temporary.replace(path)


def checked_root(path):
    raw = Path(path).absolute()
    root = raw.resolve(strict=True)
    if raw != root or root.parent != Path('/private/tmp') or not root.name.startswith('vale-published-upgrade.'):
        raise ValueError('Expected a dedicated real /private/tmp/vale-published-upgrade.* directory')
    attributes = root.stat()
    if not root.is_dir() or attributes.st_uid != os.getuid() or attributes.st_mode & 0o077:
        raise ValueError('Fixture directory must be user-owned and mode0700')
    return root


def read_app(app, defaults_domain=None):
    app = app.resolve(strict=True)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if (app.suffix != '.app' or info.get('CFBundleIdentifier') != BUNDLE_ID
            or info.get('CFBundleExecutable') != 'Lilt' or info.get('SUFeedURL') != FEED
            or info.get('SUPublicEDKey') != PUBLIC_KEY
            or info.get('SURequireSignedFeed') is not True
            or info.get('SUVerifyUpdateBeforeExtraction') is not True
            or type(info.get('SUSignedFeedFailureExpirationInterval')) is not int
            or info['SUSignedFeedFailureExpirationInterval'] != 0
            or info.get('SUEnableAutomaticChecks') is not True
            or info.get('SUAutomaticallyUpdate') is not True
            or not isinstance(info.get('CFBundleVersion'), str)
            or not re.fullmatch(r'[0-9]+', info['CFBundleVersion'])
            or info.get('SUDefaultsDomain') != defaults_domain
            or info.get('NSAppTransportSecurity')):
        raise ValueError('Expected a strictly configured production Vale bundle')
    command(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
    return info


def tree_fingerprint(app):
    records = []
    for path in sorted(app.rglob('*')):
        name = str(path.relative_to(app))
        if path.is_symlink():
            path.resolve(strict=True).relative_to(app.resolve())
            records.append([name, 'link', os.readlink(path)])
        elif path.is_file():
            records.append([name, 'file', path.stat().st_size, digest(path)])
    return hashlib.sha256(json.dumps(records, separators=(',', ':')).encode()).hexdigest()


def extract_checked(archive, destination):
    with zipfile.ZipFile(archive) as source:
        members = source.infolist()
        if len(members) > 10000 or sum(item.file_size for item in members) > 256 * 1024 * 1024:
            raise ValueError('Unexpectedly large update archive')
        for item in members:
            name = PurePosixPath(item.filename)
            if name.is_absolute() or '..' in name.parts or '\\' in item.filename or not name.parts:
                raise ValueError('Unsafe archive member')
            if name.parts[0] not in ('Vale.app', '__MACOSX'):
                raise ValueError('Update archive must contain only Vale.app and resource forks')
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                target = source.read(item).decode('utf-8')
                resolved = posixpath.normpath(posixpath.join(str(name.parent), target))
                if target.startswith('/') or not resolved.startswith(name.parts[0] + '/'):
                    raise ValueError('Archive symlink escapes its app')
    command(['/usr/bin/ditto', '-x', '-k', archive, destination])
    return destination / 'Vale.app'


def prepare(args):
    os.umask(0o077)
    old = args.old_app.resolve(strict=True)
    old_info = read_app(old)
    sdk = args.sdk.resolve(strict=True)
    framework = sdk / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    framework_info = plistlib.loads((framework / 'Resources/Info.plist').read_bytes())
    if framework_info.get('CFBundleShortVersionString') != '2.10.0':
        raise ValueError('This harness is reviewed for the pinned Sparkle2.10.0')
    command(['/usr/bin/codesign', '--verify', '--deep', '--strict', framework])
    if args.output_private:
        requested = args.output_private.absolute()
        if requested.parent != Path('/private/tmp') or not requested.name.startswith('vale-published-upgrade.'):
            raise ValueError('--output-private must be a new dedicated directory under /private/tmp')
        requested.mkdir(mode=0o700)
        root = checked_root(requested)
    else:
        root = checked_root(tempfile.mkdtemp(prefix='vale-published-upgrade.', dir='/private/tmp'))
    expected_directory = root / 'expected'
    expected_directory.mkdir()
    if args.expected_archive:
        expected_archive = args.expected_archive.resolve(strict=True)
        expected = extract_checked(expected_archive, expected_directory)
        archive_hash = digest(expected_archive)
    else:
        expected = expected_directory / 'Vale.app'
        command(['/usr/bin/ditto', args.expected_app.resolve(strict=True), expected])
        archive_hash = None
    expected_info = read_app(expected)
    if int(expected_info['CFBundleVersion']) <= int(old_info['CFBundleVersion']):
        raise ValueError('Expected payload must be newer than the copied published old app')
    version = expected_info['CFBundleShortVersionString']
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}', version):
        raise ValueError('Expected a numeric published release version')
    expected_url = args.expected_url or f'https://github.com/AgarwalAarush/Vale/releases/download/v{version}/Vale-{version}-macOS-universal.zip'
    url = urllib.parse.urlsplit(expected_url)
    if (url.scheme != 'https' or url.netloc != 'github.com' or url.query or url.fragment
            or not re.fullmatch(r'/AgarwalAarush/Vale/releases/download/[A-Za-z0-9._-]+/Vale-[A-Za-z0-9._-]+-macOS-universal\.zip', url.path)):
        raise ValueError('Expected a versioned public Vale HTTPS archive URL')
    fixture_id = 'local.vale.publishedupgrade.' + uuid.uuid4().hex
    defaults_id = fixture_id + '.host'
    target = root / 'installed/Vale.app'
    target.parent.mkdir()
    old_source_fingerprint = tree_fingerprint(old)
    command(['/usr/bin/ditto', old, target])
    private_info = dict(old_info, SUDefaultsDomain=defaults_id)
    (target / 'Contents/Info.plist').write_bytes(plistlib.dumps(private_info))
    command(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', BUNDLE_ID, target])
    command(['/usr/bin/codesign', '--verify', '--deep', '--strict', target])
    if tree_fingerprint(old) != old_source_fingerprint:
        raise ValueError('The supplied old app changed during preparation')
    driver = root / 'Published Upgrade.app'
    contents = driver / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Frameworks').mkdir()
    command(['/usr/bin/ditto', framework, contents / 'Frameworks/Sparkle.framework'])
    driver_info = {'CFBundleIdentifier':fixture_id, 'CFBundleExecutable':'PublishedUpgrade',
                   'CFBundleName':'Published Upgrade Fixture', 'CFBundlePackageType':'APPL',
                   'CFBundleVersion':'1', 'LSMinimumSystemVersion':'14.0', 'LSUIElement':True,
                   'PublishedUpgradeRoot':str(root)}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(driver_info))
    cache = root / 'module-cache'
    cache.mkdir()
    command(['/usr/bin/xcrun', 'clang', '-fobjc-arc', '-fmodules', f'-fmodules-cache-path={cache}',
             '-mmacosx-version-min=14.0', '-F', framework.parent, '-framework', 'Cocoa',
             '-framework', 'Sparkle', '-Wl,-rpath,@executable_path/../Frameworks',
             HERE / 'PublishedUpgradeFixture.m', '-o', contents / 'MacOS/PublishedUpgrade'], timeout=120)
    command(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', fixture_id, driver])
    command(['/usr/bin/codesign', '--verify', '--deep', '--strict', driver])
    generated = root / 'generated-preservation'
    generated.mkdir()
    sentinel_bytes = {'draft.txt':b'Generated unsent published-upgrade draft.\n',
                      'note.txt':b'Generated published-upgrade note.\n',
                      'attachment.txt':b'Generated retained attachment.\n'}
    for name, data in sentinel_bytes.items():
        (generated / name).write_bytes(data)
    request = {'schema':1, 'root':str(root), 'fixtureBundleID':fixture_id, 'defaultsDomain':defaults_id,
               'sourceRevision':args.source_revision, 'feedURL':FEED, 'expectedURL':expected_url,
               'oldVersion':old_info['CFBundleShortVersionString'], 'oldBuild':old_info['CFBundleVersion'],
               'oldSourceExecutableSHA256':digest(old / 'Contents/MacOS/Lilt'),
               'oldSourceTreeSHA256':old_source_fingerprint,
               'oldPreparedExecutableSHA256':digest(target / 'Contents/MacOS/Lilt'),
               'oldPreparedTreeSHA256':tree_fingerprint(target),
               'expectedVersion':version, 'expectedBuild':expected_info['CFBundleVersion'],
               'expectedExecutableSHA256':digest(expected / 'Contents/MacOS/Lilt'),
               'expectedInstructionSectionsSHA256':executable_code_digest(expected / 'Contents/MacOS/Lilt'),
               'expectedTreeSHA256':tree_fingerprint(expected), 'expectedArchiveSHA256':archive_hash,
               'driverExecutableSHA256':digest(contents / 'MacOS/PublishedUpgrade'),
               'sdkVersion':'2.10.0', 'sdkSHA256':digest(framework / 'Sparkle'),
               'helperSourceSHA256':digest(HERE / 'PublishedUpgradeFixture.m'),
               'runnerSourceSHA256':digest(Path(__file__)),
               'generatedSentinels':{name:digest(generated / name) for name in sentinel_bytes},
               'hostPlistChanges':{'SUDefaultsDomain':{'old':old_info.get('SUDefaultsDomain'), 'copy':defaults_id}},
               'boundary':'Copied old host ad-hoc resigned only for nonce SUDefaultsDomain. Original and expected payload unchanged. Prepare does not launch or contact the feed.'}
    save(root / 'prepared.json', request)
    print(json.dumps({'preparedRoot':str(root), 'expectedVersion':version, 'expectedBuild':request['expectedBuild'],
                      'appLaunched':False, 'productionSigningKeyAccessed':False}, indent=2))


def events_at(root):
    receipts = []
    for file in sorted(root.glob('event-*.json')):
        if file.is_symlink() or file.stat().st_size > 65536:
            raise ValueError('Unexpected fixture event file')
        value = json.loads(file.read_text())
        if isinstance(value, dict) and isinstance(value.get('event'), str):
            receipts.append(value)
    return receipts


def run(args):
    if not args.authorize_gui_and_sdk_cache:
        raise ValueError('Run requires --authorize-gui-and-sdk-cache; prepare alone never launches')
    os.umask(0o077)
    root = checked_root(args.root)
    prepared_file = root / 'prepared.json'
    if prepared_file.is_symlink():
        raise ValueError('Prepared receipt must be a real private file')
    request = json.loads(prepared_file.read_text())
    if (request.get('schema') != 1 or request.get('root') != str(root)
            or not re.fullmatch(r'local\.vale\.publishedupgrade\.[0-9a-f]{32}', request.get('fixtureBundleID', ''))
            or request.get('defaultsDomain') != request['fixtureBundleID'] + '.host'
            or request.get('feedURL') != FEED):
        raise ValueError('Invalid prepared fixture request')
    if (root / 'run-started.json').exists() or list(root.glob('event-*.json')):
        raise ValueError('Refusing to reuse a fixture/defaults domain')
    target = root / 'installed/Vale.app'
    expected = root / 'expected/Vale.app'
    driver = root / 'Published Upgrade.app'
    if any(path.resolve(strict=True) != path for path in (target, expected, driver)):
        raise ValueError('Prepared bundle directories must not redirect through symlinks')
    executable = target / 'Contents/MacOS/Lilt'
    driver_executable = driver / 'Contents/MacOS/PublishedUpgrade'
    if (digest(driver_executable) != request['driverExecutableSHA256']
            or tree_fingerprint(target) != request['oldPreparedTreeSHA256']
            or tree_fingerprint(expected) != request['expectedTreeSHA256']):
        raise ValueError('Prepared fixture bytes changed; no app launched')
    read_app(target, defaults_domain=request['defaultsDomain'])
    read_app(expected)
    command(['/usr/bin/codesign', '--verify', '--deep', '--strict', driver])
    save(root / 'run-started.json', {'time':time.time(), 'preparedSHA256':digest(prepared_file), 'fixtureBundleID':request['fixtureBundleID']})
    with (root / 'driver-output.log').open('xb') as log:
        process = subprocess.Popen([str(driver_executable)], stdout=log, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 230
        while time.monotonic() < deadline:
            receipts = events_at(root)
            names = {value['event'] for value in receipts}
            if optional_digest(executable) == request['expectedExecutableSHA256'] and process.poll() is not None:
                break
            if process.poll() is not None and ('sdk-abort' in names or 'self-timeout' in names or any(name.startswith('refused-') for name in names)):
                break
            if process.poll() is not None and 'ready-on-quit' not in names:
                break
            time.sleep(0.25)
        receipts = events_at(root)
        names = {value['event'] for value in receipts}
        installed_hash = optional_digest(executable)
        checks = {
            'externalDriverStarted': 'driver-started' in names,
            'actualSDKVerifiedProductionFeed': 'verified-production-feed-loaded' in names,
            'expectedProductionArchiveRequested': any(value.get('event') == 'archive-request' and value.get('expectedHTTPSURL') is True for value in receipts),
            'automaticDefaultsObserved': any(value.get('event') == 'updater-started' and value.get('automaticChecks') is True and value.get('automaticDownloads') is True for value in receipts),
            'archiveDownloaded': 'archive-downloaded' in names,
            'archiveVerifiedAndExtracted': 'archive-verified-and-extracted' in names,
            'readyOnQuit': 'ready-on-quit' in names,
            'normalDriverQuit': 'normal-driver-quit' in names and process.poll() == 0,
            'newExecutableInstalled': installed_hash == request['expectedExecutableSHA256'],
            'noSDKAbort': 'sdk-abort' not in names,
            'generatedExternalSentinelsPreserved': all(digest(root / 'generated-preservation' / name) == value for name, value in request['generatedSentinels'].items()),
        }
        preference_read = subprocess.run(['/usr/bin/defaults', 'read', request['defaultsDomain'], 'PublishedUpgradeSentinel'], capture_output=True, timeout=10) if 'driver-started' in names else None
        preference = preference_read.stdout.decode().strip() if preference_read is not None and preference_read.returncode == 0 else ''
        checks['generatedNoncePreferencePreserved'] = preference == 'Generated published-upgrade preference'
        if checks['newExecutableInstalled']:
            installed_info = read_app(target)
            checks['installedIdentityAndVersion'] = (installed_info['CFBundleVersion'] == request['expectedBuild'] and installed_info['CFBundleShortVersionString'] == request['expectedVersion'])
            checks['exactExpectedBundleTreeInstalled'] = tree_fingerprint(target) == request['expectedTreeSHA256']
        else:
            checks['installedIdentityAndVersion'] = False
            checks['exactExpectedBundleTreeInstalled'] = False
        checks['nonceCloneMatchesInstalledInstructionSections'] = False
        checks['newCodeNonceCloneLaunchedInIsolatedMode'] = False
        native_status = None
        execution_info_changes = None
        # Exact production payload bytes have already been proven installed.
        # --self-test isolates the app library/updater, but UserDefaults.standard
        # follows the main bundle ID. Reidentify a separate execution clone so
        # even ordinary model preferences cannot enter the personal Vale domain.
        if all(value for key, value in checks.items() if key not in ('nonceCloneMatchesInstalledInstructionSections', 'newCodeNonceCloneLaunchedInIsolatedMode')):
            execution = root / 'execution/Vale.app'
            execution.parent.mkdir()
            command(['/usr/bin/ditto', target, execution])
            execution_info = plistlib.loads((execution / 'Contents/Info.plist').read_bytes())
            original_execution_info = dict(execution_info)
            execution_info['CFBundleIdentifier'] = request['fixtureBundleID'] + '.execution'
            execution_info.pop('SUDefaultsDomain', None)
            (execution / 'Contents/Info.plist').write_bytes(plistlib.dumps(execution_info))
            command(['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', execution_info['CFBundleIdentifier'], execution])
            command(['/usr/bin/codesign', '--verify', '--deep', '--strict', execution])
            execution_info_changes = {key:{'installed':original_execution_info.get(key), 'clone':execution_info.get(key)} for key in original_execution_info.keys() | execution_info.keys() if original_execution_info.get(key) != execution_info.get(key)}
            if set(execution_info_changes) != {'CFBundleIdentifier'}:
                raise ValueError('Unexpected execution-clone metadata change')
            clone_executable = execution / 'Contents/MacOS/Lilt'
            checks['nonceCloneMatchesInstalledInstructionSections'] = executable_code_digest(clone_executable) == request['expectedInstructionSectionsSHA256']
            if not checks['nonceCloneMatchesInstalledInstructionSections']:
                raise ValueError('Execution clone instruction sections differ from exact payload')
            native_output = root / 'new-executable-check'
            environment = dict(os.environ)
            if request.get('sourceRevision'):
                environment['VALE_EVIDENCE_HEAD'] = request['sourceRevision']
            with (root / 'new-executable-output.log').open('xb') as native_log:
                native = subprocess.Popen([str(clone_executable), '--self-test', str(native_output)], stdout=native_log, stderr=subprocess.STDOUT, env=environment)
                try:
                    native_status = native.wait(timeout=240)
                except subprocess.TimeoutExpired:
                    # No force kill: only the isolated app was launched. Root
                    # receives its exact PID and can inspect it if it did not exit.
                    native_status = 'timeout; isolated PID ' + str(native.pid)
            result_file = native_output / 'results.json'
            if result_file.is_file():
                native_results = json.loads(result_file.read_text())
                checks['newCodeNonceCloneLaunchedInIsolatedMode'] = native_status == 0 and bool(native_results) and all(value is True for value in native_results.values())
        result = {'schema':1, 'passed':all(checks.values()), 'checks':checks,
                  'preparedSHA256':digest(prepared_file), 'sourceRevision':request.get('sourceRevision'),
                  'oldVersion':request['oldVersion'], 'oldBuild':request['oldBuild'],
                  'expectedVersion':request['expectedVersion'], 'expectedBuild':request['expectedBuild'],
                  'installedExecutableSHA256':installed_hash,
                  'oldPreparedExecutableUnchanged':installed_hash == request['oldPreparedExecutableSHA256'],
                  'oldPreparedBundleUnchanged':tree_fingerprint(target) == request['oldPreparedTreeSHA256'],
                  'driverExit':process.poll(), 'driverPID':process.pid, 'nativeExit':native_status,
                  'executionClonePlistChanges':execution_info_changes,
                  'events':receipts, 'ordinaryValeLaunchedByHarness':False, 'productionSigningKeyAccessed':False,
                  'boundary':'Actual pinned SDK, production HTTPS signed feed/archive and copied real old host. Exact published app bytes installed/signature verified before a controlled bundle-ID/ad-hoc-signature clone runs --self-test with a disposable test-library and nonce preferences. Clone __TEXT,__text instruction sections match exact installed payload. No ordinary legacy-ID Vale launch or exact published executable launch claim. Sentinels prove external generated bytes/preferences survived; not actual old user-store migration, laptop install, hardware, account inference or notarization. Stock SDK cache/service namespaces use legacy host ID; preferences are nonce isolated. No personal prefs or app data are read/written.'}
        save(root / 'result.json', result)
        print(json.dumps(result, indent=2))
        if not result['passed']:
            raise RuntimeError('Published upgrade verification failed; see private result.json; no host app force-quit or rollback attempted')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    actions = parser.add_subparsers(dest='action')
    actions.add_parser('plan')
    preparer = actions.add_parser('prepare')
    preparer.add_argument('--old-app', required=True, type=Path)
    expected = preparer.add_mutually_exclusive_group(required=True)
    expected.add_argument('--expected-app', type=Path)
    expected.add_argument('--expected-archive', type=Path)
    preparer.add_argument('--sdk', required=True, type=Path, help='Pinned Sparkle artifact directory containing Sparkle.xcframework')
    preparer.add_argument('--expected-url', help='Versioned github.com/AgarwalAarush/Vale full archive URL')
    preparer.add_argument('--output-private', type=Path)
    preparer.add_argument('--source-revision', help='Optional exact40-character source revision for native PNG metadata')
    runner = actions.add_parser('run')
    runner.add_argument('root', type=Path)
    runner.add_argument('--authorize-gui-and-sdk-cache', action='store_true')
    args = parser.parse_args()
    if args.action == 'prepare':
        if args.source_revision is not None and not re.fullmatch(r'[0-9a-f]{40}', args.source_revision):
            parser.error('--source-revision must be a full lowercase Git revision')
        prepare(args)
    elif args.action == 'run':
        run(args)
    else:
        print(json.dumps({'default':'plan-only; no writes, network or launch',
                          'prepare':'Copies only under a new private/tmp root; compiles/ad-hoc signs nonce driver and private old-host copy.',
                          'run':'Explicit gate; actual production HTTPS SDK upgrade, ordinary nonce-driver quit, exact payload/signature check, then controlled nonce clone of new code runs its isolated self-test.',
                          'boundary':'Does not launch ordinary Vale, read personal store/prefs or read/sign with production private keys. SDK host-ID cache and service namespace are not nonce-isolated.'}, indent=2))


if __name__ == '__main__':
    main()
