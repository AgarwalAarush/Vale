#!/usr/bin/env python3
"""Prepare verified, unpublished Vale artifacts. Never sign updates or read private keys."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile

ROOT = Path(__file__).resolve().parent.parent
KNOWN_WEB_FAILURE = 'explicitWebSearchUsesRealTool'
FEED = 'https://github.com/AgarwalAarush/Vale/releases/latest/download/appcast.xml'
CASES = ('valid', 'feed-tamper', 'archive-tamper')
NATIVE_PNGS = (
    '01-new-chat.png', '03-attachments.png', '04-PDF-preview.png', '05-paused.png',
    '06-optional-learn-mode.png', '08-chat-history.png', '09-settings-updates.png',
    '09b-update-controls.png', '10-recovery.png', '12-live-context.png',
    '13-loading.png', '14-window-changed.png', '15-error-retry.png',
    '17-conversation.png', '19-step-guide.png', '20-occluded-highlight.png',
    '21-context-limit.png', '22-deletion-error.png', '23-forget-recovered.png',
    'workspace-01-empty-light.png', 'workspace-02-conversation-light.png',
    'workspace-03-settings-light.png', 'workspace-03b-settings-active-voice.png', 'workspace-04-notes-light.png',
    'workspace-05-files-light.png', 'workspace-06-pdf-light.png',
    'workspace-07-search-light.png', 'workspace-08-conversation-dark.png',
    'workspace-09-settings-dark.png', 'workspace-10-compact-chat.png',
    'workspace-11-compact-notes.png', 'workspace-11b-compact-history.png', 'workspace-12-wide-notes.png',
)
INTEGRATION_PNGS = ('07-real-general-reply.png', '11-live-web-search.png', '24-real-guide-synthetic-screen.png')
SECRET_PATTERNS = (
    rb'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----',
    rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    rb'\bgh[pousr]_[A-Za-z0-9]{30,}\b',
    rb'\bgithub_pat_[A-Za-z0-9_]{40,}\b',
    rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}\b',
)
TEXT_SUFFIXES = {'.swift', '.py', '.m', '.h', '.md', '.json', '.plist', '.txt', '.yml', '.yaml', '.sh', '.command', '.toml', '.xml'}


def command(*args):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f'{Path(str(args[0])).name} failed ({result.returncode}). No publication was attempted.')
    return (result.stdout + result.stderr).strip()


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1_048_576), b''):
            value.update(chunk)
    return value.hexdigest()


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def read_json(path):
    if unsafe_name(path.name) or path.is_symlink() or not path.is_file():
        raise SystemExit(f'Missing regular evidence file: {path}')
    return json.loads(path.read_text())


def results(path, *, allow_web=False, integration=False):
    values = read_json(path)
    if not isinstance(values, dict) or not values or not all(type(v) is bool for v in values.values()):
        raise SystemExit(f'Expected a nonempty unchanged boolean result map: {path}')
    failed = sorted(k for k, v in values.items() if not v)
    if integration and KNOWN_WEB_FAILURE not in values:
        raise SystemExit('Integration evidence is missing the Web assertion; it may not be omitted.')
    if failed and not (allow_web and integration and failed == [KNOWN_WEB_FAILURE]):
        raise SystemExit(f'Verification failed at {path.name}: {", ".join(failed)}')
    return {'passed': sum(values.values()), 'total': len(values), 'failed': failed, 'results': values}


def unsafe_name(name):
    parts = PurePosixPath(name).parts
    base = parts[-1] if parts else ''
    return (any(p in {'.git', '.aws', '.codex', 'test-library', 'node_modules'} for p in parts)
            or base in {'auth.json', 'credentials', 'sessions.json', 'sessions-v1-backup.json'}
            or (base.startswith('.env') and base != '.env.example')
            or base.lower().endswith(('.key', '.pem', '.p12', '.pfx'))
            or base.startswith('test-seed'))


def scan_bytes(name, data):
    if any(re.search(pattern, data) for pattern in SECRET_PATTERNS):
        raise SystemExit(f'Possible credential material in staged entry: {name} (contents suppressed)')
    if PurePosixPath(name).suffix.lower() in TEXT_SUFFIXES and str(Path.home()).encode() in data:
        raise SystemExit(f'Local home path in staged text entry: {name} (contents suppressed)')


def scan_bundle(app):
    for path in app.rglob('*'):
        relative = path.relative_to(app).as_posix()
        if unsafe_name(relative):
            raise SystemExit(f'Forbidden data/credential path in app: {relative}')
        if path.is_symlink():
            if not path.resolve().is_relative_to(app.resolve()):
                raise SystemExit(f'App symlink escapes its bundle: {relative}')
        elif path.is_file():
            scan_bytes(relative, path.read_bytes())


def validate_config(info, pinned):
    feed, key = info.get('SUFeedURL'), info.get('SUPublicEDKey')
    if not isinstance(feed, str) or not isinstance(key, str):
        raise SystemExit('The bootstrap bundle requires a real feed and public key.')
    try:
        url = urllib.parse.urlsplit(feed)
        decoded = base64.b64decode(key, validate=True)
        port = url.port
    except ValueError:
        raise SystemExit('Invalid public update configuration.')
    if (feed != FEED or feed != pinned.get('SUFeedURL') or key != pinned.get('SUPublicEDKey')
            or url.scheme != 'https' or not url.hostname or url.username is not None
            or url.password is not None or url.fragment or port not in (None, 443)
            or any(c.isspace() for c in feed) or len(decoded) != 32):
        raise SystemExit('Built update configuration differs from the pinned production HTTPS source/key.')
    if (info.get('SURequireSignedFeed') is not True or info.get('SUVerifyUpdateBeforeExtraction') is not True
            or type(info.get('SUSignedFeedFailureExpirationInterval')) not in (int, float)
            or info['SUSignedFeedFailureExpirationInterval'] != 0
            or info.get('SUEnableAutomaticChecks') is not True
            or info.get('SUAutomaticallyUpdate') is not True
            or info.get('SUAllowsAutomaticUpdates') is False):
        raise SystemExit('The bootstrap requires strict verification and enabled automatic defaults.')
    return {
        'framework': 'Sparkle 2.10.0', 'configured': True, 'feedURL': feed,
        'publicKeySHA256': hashlib.sha256(decoded).hexdigest(),
        'signedFeedRequired': True, 'verificationBeforeExtraction': True,
        'signedFeedFailureExpirationInterval': 0,
        'automaticChecks': info['SUEnableAutomaticChecks'],
        'automaticDownloadsAndInstall': info['SUAutomaticallyUpdate'],
        'preferencesAreDefaults': True, 'savedUserPreferencesPreserved': True,
        'bootstrapRequiredForUnconfiguredBuilds': True,
        'productionFeedPublished': False, 'productionHTTPSVerified': False,
        'archiveAndFeedSigning': 'parent-owned; not performed by packaging',
    }


def sparkle_receipts(args, series):
    paths = {case: ROOT / f'artifacts/sparkle-upgrade-{case}-{series}.json' for case in CASES}
    for supplied in args.sparkle_receipt:
        case, separator, name = supplied.partition('=')
        if not separator or case not in CASES or not name:
            raise SystemExit('--sparkle-receipt requires valid|feed-tamper|archive-tamper=PATH')
        paths[case] = Path(name).expanduser().absolute()
    receipts = {}
    for case, path in paths.items():
        value = read_json(path)
        checks = value.get('checks', {})
        required = ({'automaticDefaultsObserved', 'archiveFetched', 'readyOnQuit', 'newExecutableInstalled',
                     'newCompiledBinaryLaunched', 'generatedDataPreserved'} if case == 'valid' else
                    {'SDKCryptographicRejection', 'oldExecutablePreserved', 'noInstallReady', 'expectedArchiveFetch'})
        if (value.get('case') != case or value.get('passed') is not True or not checks
                or not required.issubset(checks) or not all(v is True for v in checks.values())
                or (case == 'valid' and value.get('mode') != 'relaunch')):
            raise SystemExit(f'Real SDK receipt has not passed its required checks: {case}')
        # Explicit public receipt schema; never copy arbitrary strings, paths, logs or test data.
        receipts[case] = {
            'case': case, 'mode': value.get('mode'), 'passed': True, 'checks': checks,
            'installedExecutableSHA256': value.get('installedExecutableSHA256'),
            'runnerRelaunchAfterNormalQuit': value.get('runnerRelaunchAfterNormalQuit') is True,
            'transport': 'loopback HTTP fixture', 'signing': 'ad-hoc app plus disposable Ed25519 fixture key',
            'productionHTTPSVerified': False,
        }
    return receipts


def validate_evidence_png(path, expected_head):
    """Admit only exact-source, explicitly generated full-window native evidence."""
    path = Path(path)
    if path.is_symlink() or not path.is_file():
        raise SystemExit(f'Missing regular screenshot: {path.name}')
    metadata = read_json(path.with_suffix(path.suffix + '.json'))
    allowed = {'generated-accountless-harness', 'generated-disposable-fixture'}
    if (not re.fullmatch(r'[0-9a-f]{40}', expected_head)
            or metadata.get('sourceRevision') != expected_head
            or metadata.get('captureProvenance') not in allowed
            or metadata.get('generatedTestDataOnly') is not True
            or metadata.get('publicArchiveEligible') is not True
            or metadata.get('method') != 'in-process-full-window-raster'
            or metadata.get('includesWindowControlsInHierarchy') is not True):
        raise SystemExit(f'Private, unknown, or stale screenshot refused for public archive: {path.name}')
    data = path.read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n') or metadata.get('pngSHA256') != hashlib.sha256(data).hexdigest():
        raise SystemExit(f'Invalid or unbound evidence PNG: {path.name}')
    scan_bytes(path.name, data)
    scan_bytes(path.name + '.json', json_bytes(metadata))
    return data, metadata


def add_evidence(archive, prefix, summaries, series):
    expected_head = command('git', 'rev-parse', 'HEAD')
    for name, value in summaries.items():
        data = json_bytes(value)
        scan_bytes(name, data)
        archive.writestr(prefix + 'evidence/' + name, data)
    for folder, names in ((f'native-ui-{series}-final', NATIVE_PNGS),
                          (f'integration-{series}-final', INTEGRATION_PNGS)):
        for name in names:
            path = ROOT / 'artifacts' / folder / name
            if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to((ROOT / 'artifacts').resolve()):
                raise SystemExit(f'Missing regular allowlisted screenshot: {folder}/{name}')
            data, metadata = validate_evidence_png(path, expected_head)
            # A failed Web attempt remains evidence, without presenting its filename as a successful search.
            output_name = '11-web-search-attempt.png' if name == '11-live-web-search.png' else name
            archive.writestr(prefix + 'evidence/' + folder + '/' + output_name, data)
            archive.writestr(prefix + 'evidence/' + folder + '/' + output_name + '.json', json_bytes(metadata))


def audit_source_zip(path, prefix):
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            relative = name.removeprefix(prefix)
            parts = PurePosixPath(name).parts
            if not name.startswith(prefix) or '..' in parts or PurePosixPath(name).is_absolute() or unsafe_name(relative):
                raise SystemExit(f'Forbidden source archive entry: {name}')
            if entry.is_dir():
                continue
            data = archive.read(entry)
            mode = entry.external_attr >> 16
            if stat.S_ISLNK(mode):
                target = data.decode('utf-8')
                resolved = os.path.normpath(str(PurePosixPath(name).parent / target))
                if PurePosixPath(target).is_absolute() or not resolved.startswith(prefix):
                    raise SystemExit(f'Source archive symlink escapes its root: {name}')
            else:
                scan_bytes(relative, data)


def plan(args):
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    print(json.dumps({
        'planOnly': True, 'version': version, 'build': info['CFBundleVersion'],
        'strictIntegrationGate': not args.private_candidate_allow_known_web_unavailable,
        'onlyPermittedKnownFailure': KNOWN_WEB_FAILURE if args.private_candidate_allow_known_web_unavailable else None,
        'requiredResults': [
            f'artifacts/core-results-{version}.json',
            f'artifacts/native-ui-{version}-final/results.json',
            f'artifacts/native-ui-{version}-repeat/results.json OR native-ui-{version}-repeat.log',
            f'artifacts/integration-{version}-final/results.json',
            'artifacts/update-build-config-results.json',
            *[f'artifacts/sparkle-upgrade-{case}-{version}.json OR --sparkle-receipt {case}=PATH' for case in CASES],
        ],
        'outputs': [f'dist/Vale-{version}-{suffix}' for suffix in (
            'macOS-universal.zip', 'laptop-setup.zip', 'laptop-setup.dmg',
            'source-and-evidence.zip', 'release-manifest.json', 'SHA256SUMS.txt')],
        'requiresCleanCommittedSource': True, 'signsOrPublishes': False,
    }, indent=2))


def package(args):
    if command('git', 'status', '--porcelain', '--untracked-files=all'):
        raise SystemExit('Commit/reconcile source changes before packaging; ignored artifacts are allowed.')
    pinned = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    app = ROOT / 'dist/Vale.app'
    if app.is_symlink() or not app.is_dir():
        raise SystemExit('Build a real dist/Vale.app before packaging.')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if (not re.fullmatch(r'\d+(?:\.\d+)*', version) or not re.fullmatch(r'\d+(?:\.\d+)*', build)
            or (version, build) != (pinned['CFBundleShortVersionString'], pinned['CFBundleVersion'])
            or info['CFBundleIdentifier'] != 'local.lilt.companion' or info['CFBundleExecutable'] != 'Lilt'):
        raise SystemExit('Built identity/version does not match the frozen source.')
    updater = validate_config(info, pinned)
    checks = {
        'core': results(ROOT / f'artifacts/core-results-{version}.json'),
        'native': results(ROOT / f'artifacts/native-ui-{version}-final/results.json'),
        'integration': results(ROOT / f'artifacts/integration-{version}-final/results.json',
                               allow_web=args.private_candidate_allow_known_web_unavailable, integration=True),
        'updateBuildConfiguration': results(ROOT / 'artifacts/update-build-config-results.json'),
    }
    repeat_path = ROOT / f'artifacts/native-ui-{version}-repeat/results.json'
    if not repeat_path.exists():
        repeat_path = ROOT / f'artifacts/native-ui-{version}-repeat.log'
    checks['nativeRepeat'] = results(repeat_path)
    sdk = sparkle_receipts(args, version)
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    architectures = sorted(command('/usr/bin/lipo', '-archs', app / 'Contents/MacOS/Lilt').split())
    if set(architectures) != {'x86_64', 'arm64'}:
        raise SystemExit('Build VALE_ARCH=universal before packaging.')
    signing = command('/usr/bin/codesign', '--display', '--verbose=4', app)
    adhoc = 'Signature=adhoc' in signing
    framework_info = plistlib.loads((app / 'Contents/Frameworks/Sparkle.framework/Resources/Info.plist').read_bytes())
    updater['framework'] = 'Sparkle ' + framework_info['CFBundleShortVersionString']
    if framework_info['CFBundleShortVersionString'] != '2.10.0':
        raise SystemExit('Unexpected embedded Sparkle version.')
    scan_bundle(app)
    web_unavailable = checks['integration']['failed'] == [KNOWN_WEB_FAILURE]
    remaining = [
        'Final publication approval and live signed HTTPS feed/archive verification',
        'One-time configured bootstrap install for unconfigured older builds',
        'Target laptop installation, Gatekeeper and Apple Silicon runtime',
        'Developer ID/notarized distribution is not established by ad-hoc private signing',
        'Real microphone/window consent, VoiceOver and multi-display hardware acceptance',
    ]
    if web_unavailable:
        remaining.insert(0, 'Web search unavailable in tested CLI/runtime with execution tools disabled')
    manifest = {
        'product': info['CFBundleName'], 'version': version, 'build': build,
        'bundleIdentifier': info['CFBundleIdentifier'], 'architectures': architectures,
        'minimumMacOS': info['LSMinimumSystemVersion'], 'sourceCommit': command('git', 'rev-parse', 'HEAD'),
        'appExecutableSHA256': digest(app / 'Contents/MacOS/Lilt'),
        'signature': {'kind': 'ad-hoc' if adhoc else 'code-signed', 'strictDeepVerificationPassed': True},
        'notarized': False if adhoc else None, 'notarizationVerified': False,
        'updater': updater, 'releaseReady': False,
        'status': 'private-candidate-known-web-unavailable' if web_unavailable else 'prepared-unpublished',
        'localVerificationPassed': not web_unavailable,
        'knownFailureAcknowledged': KNOWN_WEB_FAILURE if web_unavailable else None,
        'verification': checks, 'sparkleSDKFixtures': sdk,
        'runtimeVerified': {'architecture': platform.machine(), 'macOS': platform.mac_ver()[0]},
        'arm64RuntimeVerified': False, 'laptopInstalled': False,
        'published': False, 'productionFeedVerified': False,
        'integrationIncludesNativeAssertions': True, 'repeatCountsAreNotIndependentJourneys': True,
        'visualReview': 'Parent-owned; packaging does not establish screenshot acceptance',
        'remaining': remaining,
    }
    summaries = {f'{label}-results.json': value['results'] for label, value in checks.items()}
    summaries.update({f'sparkle-{case}.json': value for case, value in sdk.items()})
    for label in ('native', 'integration'):
        folder = f'{label if label == "integration" else "native-ui"}-{version}-final'
        proof = read_json(ROOT / 'artifacts' / folder / 'privacy-proof.json')
        summaries[f'{label}-privacy-proof.json'] = {
            name: proof[name] for name in ('targetID', 'remainingSessionIDs', 'remainingBackupIDs',
                                          'targetBytesRemoved', 'unrelatedBytesPreserved')
        }
    summaries['verification-summary.json'] = manifest
    dist = ROOT / 'dist'
    with tempfile.TemporaryDirectory(prefix='.vale-package-', dir=dist) as directory:
        staging = Path(directory)
        update_zip = staging / f'Vale-{version}-macOS-universal.zip'
        command('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, update_zip)
        command('/usr/bin/unzip', '-t', update_zip)
        source_zip = staging / f'Vale-{version}-source-and-evidence.zip'
        prefix = f'Vale-{version}-source/'
        command('git', 'archive', '--format=zip', f'--prefix={prefix}', f'--output={source_zip}', 'HEAD')
        with zipfile.ZipFile(source_zip, 'a', zipfile.ZIP_DEFLATED) as archive:
            add_evidence(archive, prefix, summaries, version)
        audit_source_zip(source_zip, prefix)
        verification = staging / 'verification.json'
        verification.write_bytes(json_bytes(manifest))
        setup = json.loads(command(sys.executable, ROOT / 'scripts/package-dmg.py',
                                   '--app', app, '--verification', verification, '--output-dir', staging))
        outputs = [update_zip, source_zip, staging / setup['setupZIP'], staging / setup['setupDMG']]
        manifest['files'] = [{'name': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in outputs]
        manifest_path = staging / f'Vale-{version}-release-manifest.json'
        manifest_path.write_bytes(json_bytes(manifest))
        outputs.append(manifest_path)
        sums = staging / f'Vale-{version}-SHA256SUMS.txt'
        sums.write_text(''.join(f'{digest(p)}  {p.name}\n' for p in outputs))
        outputs.append(sums)
        # Publish only to local dist, after all preparation succeeded. No GitHub/network operation.
        for output in outputs:
            os.replace(output, dist / output.name)
    print(json.dumps({'status': manifest['status'], 'releaseReady': False,
                      'outputs': [str(dist / p.name) for p in outputs]}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', action='store_true', help='List inputs/outputs without preparing artifacts')
    parser.add_argument('--private-candidate-allow-known-web-unavailable', action='store_true',
                        help='Acknowledge only the exact failed Web assertion; retain false results and releaseReady:false')
    parser.add_argument('--sparkle-receipt', action='append', default=[], metavar='CASE=PATH',
                        help='Explicit real SDK result.json for valid, feed-tamper or archive-tamper')
    args = parser.parse_args()
    if args.plan:
        plan(args)
    else:
        package(args)


if __name__ == '__main__':
    main()
