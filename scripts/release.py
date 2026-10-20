#!/usr/bin/env python3
"""Build, sign and publish one immutable Vale automatic update. See docs/releases.md."""
import argparse
import base64
import datetime
import email.utils
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
REPO = 'AgarwalAarush/Vale'
FEED = f'https://github.com/{REPO}/releases/latest/download/appcast.xml'
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def fail(message):
    raise SystemExit(message)


def run(*args, env=None):
    result = subprocess.run([str(a) for a in args], cwd=ROOT, env=env, capture_output=True, text=True)
    if result.returncode:
        # In particular, never print sign_update output: malformed key files can be echoed by that tool.
        fail(f'{Path(str(args[0])).name} failed ({result.returncode}); output suppressed. No later release stage ran.')
    return result.stdout.strip()


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    path.chmod(0o600)


def regular(path):
    if path.is_symlink() or not path.is_file():
        fail('Expected a regular, non-symlink release file.')
    return path


def key_path():
    common = Path(run('git', 'rev-parse', '--git-common-dir'))
    if not common.is_absolute():
        common = ROOT / common
    path = Path(os.environ.get('VALE_UPDATE_SIGNING_KEY_FILE', common / 'codex-factory/private/vale-updates-v1.key')).absolute()
    # Check metadata only. The stock signer is the only process permitted to open the seed.
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            fail('The update signing key path must not traverse symlinks.')
    try:
        file_stat, directory_stat = path.lstat(), path.parent.lstat()
    except OSError:
        fail('Update signing key is unavailable; configure VALE_UPDATE_SIGNING_KEY_FILE.')
    if (not stat.S_ISREG(file_stat.st_mode) or file_stat.st_uid != os.getuid()
            or stat.S_IMODE(file_stat.st_mode) != 0o600 or directory_stat.st_uid != os.getuid()
            or stat.S_IMODE(directory_stat.st_mode) != 0o700):
        fail('The update signing seed requires an owner-only 0600 file in an owner-only 0700 directory.')
    return path


def build_number(value):
    if not isinstance(value, str) or not re.fullmatch(r'\d+(?:\.\d+)*', value):
        fail('Bundle build numbers must be numeric.')
    parts = tuple(int(x) for x in value.split('.'))
    return parts + (0,) * (8 - len(parts))


def download(url, destination):
    if not url.startswith('https://github.com/' + REPO + '/'):
        fail('Release downloads must originate at the pinned repository over HTTPS.')
    run('/usr/bin/curl', '--disable', '--fail', '--silent', '--show-error', '--location',
        '--proto', '=https', '--proto-redir', '=https', '--retry', '3', '--output', destination, url)


def verifier(mode, key, path, signature=None):
    environment = os.environ.copy()
    environment.pop('SDKROOT', None)
    sdk = run('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path', env=environment)
    cache = ROOT / '.build/module-cache-release'
    cache.mkdir(parents=True, exist_ok=True)
    environment['SDKROOT'] = sdk
    environment['CLANG_MODULE_CACHE_PATH'] = str(cache)
    args = ['swift', '-sdk', sdk, '-module-cache-path', cache,
            ROOT / 'scripts/verify-release-signatures.swift', mode, key, path]
    if signature is not None:
        args.append(signature)
    run(*args, env=environment)


def feed_tree(path, key):
    verifier('feed', key, path)
    try:
        tree = ET.fromstring(path.read_bytes())
    except ET.ParseError:
        fail('The signed production appcast is not valid XML.')
    if tree.tag != 'rss' or tree.find('channel') is None:
        fail('Expected a signed RSS production appcast.')
    return tree


def check_monotonic(tree, build):
    for item in tree.findall('./channel/item'):
        number = item.findtext(f'{{{SPARKLE}}}version')
        if number is None:
            enclosure = item.find('enclosure')
            number = enclosure.get(f'{{{SPARKLE}}}version') if enclosure is not None else None
        if number is None or build_number(build) <= build_number(number):
            fail('The candidate CFBundleVersion must be strictly newer than every published feed entry.')


def create_feed(tree, info, archive, signature, notes, output):
    check_monotonic(tree, info['CFBundleVersion'])
    channel = tree.find('channel')
    item = ET.Element('item')
    ET.SubElement(item, 'title').text = 'Vale ' + info['CFBundleShortVersionString']
    ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item, f'{{{SPARKLE}}}version').text = info['CFBundleVersion']
    ET.SubElement(item, f'{{{SPARKLE}}}shortVersionString').text = info['CFBundleShortVersionString']
    ET.SubElement(item, f'{{{SPARKLE}}}minimumSystemVersion').text = info['LSMinimumSystemVersion']
    ET.SubElement(item, 'description').text = notes
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{REPO}/releases/download/v{info["CFBundleShortVersionString"]}/{archive.name}',
        'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
        f'{{{SPARKLE}}}edSignature': signature,
    })
    channel.insert(0, item)
    output.write_bytes(ET.tostring(tree, encoding='utf-8', xml_declaration=True) + b'\n')


def inspect_app(archive, manifest, expected_info):
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        if len(names) != len(set(names)):
            fail('Duplicate app ZIP entries.')
        for entry in zipped.infolist():
            path = Path(entry.filename)
            if (path.is_absolute() or any(p in {'.', '..'} for p in entry.filename.split('/'))
                    or not path.parts or path.parts[0] not in {'Vale.app', '__MACOSX'}):
                fail('Unsafe app ZIP entry.')
            if stat.S_ISLNK(entry.external_attr >> 16):
                target = zipped.read(entry).decode('utf-8')
                resolved = Path(os.path.normpath(str(path.parent / target)))
                if Path(target).is_absolute() or not resolved.parts or resolved.parts[0] != 'Vale.app':
                    fail('App ZIP symlink escapes its bundle.')
    with tempfile.TemporaryDirectory(prefix='vale-release-app-') as folder:
        run('/usr/bin/ditto', '-x', '-k', archive, folder)
        app = Path(folder) / 'Vale.app'
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
        policy().scan_bundle(app)
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        for name in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleShortVersionString',
                     'CFBundleVersion', 'SUPublicEDKey', 'SUFeedURL', 'SURequireSignedFeed',
                     'SUVerifyUpdateBeforeExtraction', 'SUSignedFeedFailureExpirationInterval',
                     'SUEnableAutomaticChecks', 'SUAutomaticallyUpdate'):
            if info.get(name) != expected_info.get(name):
                fail('Archived app identity/update defaults differ from the reviewed source.')
        if (sha(app / 'Contents/MacOS/Lilt') != manifest['appExecutableSHA256']
                or set(run('/usr/bin/lipo', '-archs', app / 'Contents/MacOS/Lilt').split()) != {'arm64', 'x86_64'}):
            fail('Archived executable does not match its universal app receipt.')
    return info


def policy():
    spec = importlib.util.spec_from_file_location('vale_package_policy', ROOT / 'scripts/package-release.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepared_assets(folder, version, output, head):
    names = {f'Vale-{version}-{suffix}' for suffix in ('macOS-universal.zip', 'source-and-evidence.zip',
             'laptop-setup.zip', 'laptop-setup.dmg', 'release-manifest.json', 'SHA256SUMS.txt')}
    present = {p.name for p in folder.iterdir()}
    internal_extras = {'appcast.xml', f'Vale-{version}-automatic-update.json', f'Vale-{version}-update-SHA256SUMS.txt'}
    if not names.issubset(present) or not (present - names).issubset(internal_extras if folder == output else set()):
        fail('Prepared assets must contain exactly the six reviewed release files.')
    sums = regular(folder / f'Vale-{version}-SHA256SUMS.txt').read_text().splitlines()
    expected = {}
    for line in sums:
        match = re.fullmatch(r'([0-9a-f]{64})  ([A-Za-z0-9._-]+)', line)
        if not match or match[2] in expected:
            fail('Malformed or duplicate prepared checksums.')
        expected[match[2]] = match[1]
    if set(expected) != names - {f'Vale-{version}-SHA256SUMS.txt'}:
        fail('Prepared checksums do not cover exactly the five payload files.')
    for name in names:
        original = regular(folder / name)
        if name in expected and sha(original) != expected[name]:
            fail('A reviewed prepared asset changed.')
        target = output / name
        if target.exists() and sha(target) != sha(original):
            fail('Existing local release asset differs; choose a fresh version.')
        if not target.exists():
            shutil.copyfile(original, target)
    manifest = json.loads((output / f'Vale-{version}-release-manifest.json').read_text())
    source = manifest.get('sourceCommit', '')
    if not re.fullmatch('[0-9a-f]{40}', source) or manifest.get('version') != version:
        fail('Prepared manifest requires an exact source revision/version.')
    run('git', 'merge-base', '--is-ancestor', source, head)
    run('git', 'diff', '--exit-code', source, head, '--', 'Sources', 'Resources', 'Package.swift', 'Package.resolved')
    source_info = plistlib.loads(run('git', 'show', f'{source}:Resources/Info.plist').encode())
    if manifest.get('build') != source_info['CFBundleVersion']:
        fail('Prepared app build differs from its source revision.')
    if (len(manifest.get('files', [])) != 4 or {item.get('name') for item in manifest.get('files', [])}
            != names - {f'Vale-{version}-SHA256SUMS.txt', f'Vale-{version}-release-manifest.json'}):
        fail('Prepared manifest must bind all four payloads.')
    for item in manifest.get('files', []):
        if item.get('name') not in names or sha(output / item['name']) != item.get('sha256') or (output / item['name']).stat().st_size != item.get('bytes'):
            fail('Prepared manifest payload binding failed.')
    source_zip = output / f'Vale-{version}-source-and-evidence.zip'
    policy().audit_source_zip(source_zip, f'Vale-{version}-source/')
    # The archive may add only already-admitted evidence; its tracked source bytes must match the exact Git commit.
    tracked = run('git', 'ls-tree', '-r', '--name-only', source).splitlines()
    with zipfile.ZipFile(source_zip) as zipped:
        if len(zipped.namelist()) != len(set(zipped.namelist())):
            fail('Duplicate source ZIP entries.')
        for name in tracked:
            contents = subprocess.run(['git', 'show', f'{source}:{name}'], cwd=ROOT, capture_output=True)
            if contents.returncode or zipped.read(f'Vale-{version}-source/{name}') != contents.stdout:
                fail('Archived source differs from its declared Git commit.')
    info = inspect_app(output / f'Vale-{version}-macOS-universal.zip', manifest, source_info)
    return manifest, info, source, sorted(output / name for name in names)


def instruction_digest(executable):
    dump = run('/usr/bin/otool', '-s', '__TEXT', '__text', executable)
    rows = [line for line in dump.splitlines() if re.match(r'^[0-9a-fA-F]{8,16}\s+[0-9a-fA-F]', line)]
    if not rows:
        fail('No native instruction sections were found in the execution clone.')
    return hashlib.sha256('\n'.join(rows).encode()).hexdigest()


def tree_digest(app):
    entries = []
    for path in sorted(app.rglob('*')):
        relative = str(path.relative_to(app))
        if path.is_symlink():
            entries.append([relative, 'link', os.readlink(path)])
        elif path.is_file():
            entries.append([relative, 'file', sha(path)])
    return hashlib.sha256(json.dumps(entries, separators=(',', ':')).encode()).hexdigest()


def isolated_native_check(app, evidence, environment):
    """Execute only a nonce-ID metadata clone; never touch the ordinary preferences domain."""
    original_info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if original_info.get('CFBundleIdentifier') != 'local.lilt.companion' or original_info.get('SUDefaultsDomain') is not None:
        fail('Expected the production bundle with no explicit shared defaults domain.')
    policy().scan_bundle(app)
    original_tree = tree_digest(app)
    original_code = instruction_digest(app / 'Contents/MacOS/Lilt')
    fixture_id = 'local.vale.releasetest.' + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='vale-release-native-', dir='/private/tmp') as directory:
        clone = Path(directory) / 'Vale.app'
        run('/usr/bin/ditto', app, clone)
        clone_info = dict(original_info, CFBundleIdentifier=fixture_id)
        (clone / 'Contents/Info.plist').write_bytes(plistlib.dumps(clone_info))
        run('/usr/bin/codesign', '--force', '--sign', '-', '--identifier', fixture_id, clone)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', clone)
        if (plistlib.loads((clone / 'Contents/Info.plist').read_bytes()) != clone_info
                or instruction_digest(clone / 'Contents/MacOS/Lilt') != original_code):
            fail('Native execution clone changed beyond the permitted bundle metadata/signature.')
        try:
            run(sys.executable, ROOT / 'scripts/run-bounded.py', '240', clone / 'Contents/MacOS/Lilt',
                '--self-test', evidence, env=environment)
        finally:
            if tree_digest(app) != original_tree:
                fail('The immutable production app changed during native verification.')
    return {'execution': 'nonce-bundle-ID-ad-hoc-execution-clone', 'bundleIdentifier': fixture_id,
            'changedInfoKeys': ['CFBundleIdentifier'], 'productionAppUnchanged': True,
            'instructionSectionsSHA256': original_code, 'strictCloneSignatureVerified': True,
            'boundary': 'Instruction-section equivalence after metadata-only re-signing; not whole-executable byte equivalence.'}


def build_assets(version, output):
    path = ROOT / 'Resources/Info.plist'
    info = plistlib.loads(path.read_bytes())
    if info['CFBundleShortVersionString'] != version:
        if build_number(version) <= build_number(info['CFBundleShortVersionString']):
            fail('New releases require a newer marketing version.')
        text = path.read_text()
        text = re.sub(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+', lambda m: m[1] + version, text)
        text = re.sub(r'(<key>CFBundleVersion</key>\s*<string>)[^<]+', lambda m: m[1] + str(int(info['CFBundleVersion']) + 1), text)
        path.write_text(text)
        run('git', 'add', '--', 'Resources/Info.plist')
        # Use the explicit automation identity when none is configured; never change global Git configuration.
        identity = subprocess.run(['git', 'var', 'GIT_AUTHOR_IDENT'], cwd=ROOT, capture_output=True)
        if identity.returncode:
            run('git', '-c', 'user.name=Codex', '-c', 'user.email=codex@local', 'commit', '-m', f'Release Vale {version}')
        else:
            run('git', 'commit', '-m', f'Release Vale {version}')
    head = run('git', 'rev-parse', 'HEAD')
    environment = os.environ.copy()
    environment['VALE_ARCH'] = 'universal'
    environment['VALE_EVIDENCE_HEAD'] = head
    environment['SDKROOT'] = run('/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path', env={k: v for k, v in environment.items() if k != 'SDKROOT'})
    environment['CLANG_MODULE_CACHE_PATH'] = str(ROOT / '.build/module-cache')
    environment['SWIFTPM_MODULECACHE_OVERRIDE'] = environment['CLANG_MODULE_CACHE_PATH']
    run('scripts/build.sh', env=environment)
    artifacts = ROOT / 'artifacts'
    artifacts.mkdir(exist_ok=True)
    native = artifacts / f'release-{version}-native'
    if native.exists():
        fail('Native release evidence already exists; inspect/remove it explicitly before rebuilding.')
    core = artifacts / f'release-{version}-core.json'
    run('swift', 'run', '--disable-sandbox', 'LiltCoreChecks', '--results', core, env=environment)
    run(sys.executable, 'scripts/check-update-config.py', env=environment)
    native_isolation = isolated_native_check(ROOT / 'dist/Vale.app', native, environment)
    checks = {}
    for label, file in (('core', core), ('configuration', artifacts / 'update-build-config-results.json'), ('native', native / 'results.json')):
        values = json.loads(file.read_text())
        if not values or any(type(v) is not bool or not v for v in values.values()):
            fail('Local release checks failed; no update was signed.')
        checks[label] = {'passed': len(values), 'resultsSHA256': sha(file)}
    checks['native']['isolation'] = native_isolation
    info = plistlib.loads((ROOT / 'dist/Vale.app/Contents/Info.plist').read_bytes())
    module = policy()
    module.scan_bundle(ROOT / 'dist/Vale.app')
    module.validate_config(info, plistlib.loads(path.read_bytes()))
    signing = subprocess.run(['/usr/bin/codesign', '--display', '--verbose=4', str(ROOT / 'dist/Vale.app')], capture_output=True, text=True)
    signature_kind = 'ad-hoc' if 'Signature=adhoc' in signing.stderr else 'code-signed'
    manifest = {'product': 'Vale', 'version': version, 'build': info['CFBundleVersion'], 'sourceCommit': head,
        'bundleIdentifier': info['CFBundleIdentifier'], 'appExecutableSHA256': sha(ROOT / 'dist/Vale.app/Contents/MacOS/Lilt'),
        'verification': checks, 'releaseReady': False, 'genuineChatGPTVerified': False, 'notarizationVerified': False,
        'published': False, 'laptopInstalled': False, 'deliveryChannel': 'automatic-update', 'softwareVerified': True,
        'signature': {'kind': signature_kind, 'strictDeepVerificationPassed': True},
        'boundary': 'Local core/configuration/native checks. Genuine account, physical-device and target-laptop acceptance remain separate.'}
    archive = output / f'Vale-{version}-macOS-universal.zip'
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', ROOT / 'dist/Vale.app', archive)
    inspect_app(archive, manifest, info)
    source_zip = output / f'Vale-{version}-source-and-evidence.zip'
    run('git', 'archive', '--format=zip', f'--prefix=Vale-{version}-source/', f'--output={source_zip}', head)
    module.audit_source_zip(source_zip, f'Vale-{version}-source/')
    proof = output / 'verification.json'
    write_json(proof, manifest)
    run(sys.executable, 'scripts/package-dmg.py', '--app', ROOT / 'dist/Vale.app', '--verification', proof, '--output-dir', output)
    proof.unlink()
    assets = [archive, source_zip, output / f'Vale-{version}-laptop-setup.zip', output / f'Vale-{version}-laptop-setup.dmg']
    manifest['files'] = [{'name': p.name, 'bytes': p.stat().st_size, 'sha256': sha(p)} for p in assets]
    manifest_path = output / f'Vale-{version}-release-manifest.json'
    write_json(manifest_path, manifest)
    assets.append(manifest_path)
    sums = output / f'Vale-{version}-SHA256SUMS.txt'
    sums.write_text(''.join(f'{sha(p)}  {p.name}\n' for p in assets))
    assets.append(sums)
    return manifest, info, head, assets


def remote_release(tag):
    # Listing distinguishes absent release from permission/network errors; no best-effort catch.
    releases = json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{REPO}/releases?per_page=100'))
    found = [release for page in releases for release in page if release['tag_name'] == tag]
    if len(found) > 1:
        fail('Ambiguous existing release tag.')
    return found[0] if found else None


def publish(tag, source, assets, notes_file, old_feed_hash, output):
    repository = json.loads(run('gh', 'api', f'repos/{REPO}'))
    if repository.get('private') is not False or repository.get('owner', {}).get('login') != 'AgarwalAarush':
        fail('Publishing requires the pinned owner-controlled public Vale repository.')
    release = remote_release(tag)
    if release is not None and not release['draft']:
        fail('This version is already public; published assets are immutable. Choose a newer version.')
    if release is None:
        run('gh', 'release', 'create', tag, '--repo', REPO, '--target', source, '--draft', '--title', 'Vale ' + tag[1:], '--notes-file', notes_file)
        release = remote_release(tag)
    if release is None or release['target_commitish'] != source or not release['draft']:
        fail('Existing draft does not match the exact reviewed source target.')
    expected = {p.name: p for p in assets}
    remote = {item['name']: item for item in release['assets']}
    if set(remote) - set(expected):
        fail('Existing draft has unexpected assets; it was not promoted.')
    with tempfile.TemporaryDirectory(prefix='vale-draft-check-') as folder:
        for name, path in expected.items():
            if name not in remote:
                run('gh', 'release', 'upload', tag, path, '--repo', REPO)
            destination = Path(folder) / name
            run('gh', 'release', 'download', tag, '--repo', REPO, '--pattern', name, '--dir', folder)
            if sha(destination) != sha(path):
                fail('Uploaded draft asset differs; it was not promoted.')
    current = output / 'production-before-promotion.xml'
    download(FEED, current)
    if sha(current) != old_feed_hash:
        fail('The production feed changed during preparation; the draft was not promoted.')
    run('gh', 'release', 'edit', tag, '--repo', REPO, '--draft=false', '--latest')
    with tempfile.TemporaryDirectory(prefix='vale-public-check-') as folder:
        for name, path in expected.items():
            downloaded = Path(folder) / name
            download(f'https://github.com/{REPO}/releases/download/{tag}/{name}', downloaded)
            if sha(downloaded) != sha(path):
                fail('PUBLIC DOWNLOAD VERIFICATION FAILED. Inspect the published release immediately.')
    current = output / 'production-after-promotion.xml'
    download(FEED, current)
    if sha(current) != sha(output / 'appcast.xml'):
        fail('LATEST FEED VERIFICATION FAILED. Inspect GitHub latest release immediately.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--plan', action='store_true', help='Print the pipeline without mutation or network access')
    parser.add_argument('--publish', action='store_true', help='Upload a verified draft, then promote its signed automatic-update feed')
    parser.add_argument('--prepare-only', action='store_true', help='Build/package/sign locally without uploading')
    parser.add_argument('--prepared-assets', type=Path, help='Reuse six immutable, reviewed release files without rebuilding')
    parser.add_argument('--notes-file', type=Path, help='Public release notes; defaults to a concise version announcement')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version) or (args.publish and args.prepare_only):
        parser.error('Use a three-component numeric version and choose --publish or --prepare-only.')
    if args.plan:
        print(json.dumps({'version': args.version, 'planOnly': True, 'networkAccess': False,
            'steps': ['clean committed source', 'reviewed assets or version commit + universal build + core/config/native checks',
                      'ZIP/DMG/source/checksums', 'verify current production feed', 'sign archive and feed with protected Ed25519 seed',
                      'public-key-only verification', 'draft upload and hash check', 'promote latest', 'anonymous download/hash/signature verification'],
            'AppleSigning': 'current build is ad-hoc; Sparkle Ed25519 signing does not establish Developer ID or notarization'}, indent=2))
        return
    if not args.publish and not args.prepare_only:
        parser.error('Choose --publish or --prepare-only; use --plan for a read-only preview.')
    if run('git', 'status', '--porcelain'):
        fail('Release requires a clean committed working tree, including the release tooling.')
    if args.publish:
        existing = remote_release('v' + args.version)
        if existing is not None and not existing['draft']:
            fail('This version is already public; published assets are immutable. Choose a newer version.')
    head = run('git', 'rev-parse', 'HEAD')
    seed = key_path()
    common = Path(run('git', 'rev-parse', '--git-common-dir'))
    common = common if common.is_absolute() else ROOT / common
    work = common / 'codex-factory/releases' / ('v' + args.version)
    work.mkdir(parents=True, exist_ok=True, mode=0o700)
    output = work / 'assets'
    output.mkdir(exist_ok=True, mode=0o700)
    binding_path = work / 'release-binding.json'
    if binding_path.exists():
        binding = json.loads(binding_path.read_text())
        if binding['toolingCommit'] != head:
            fail('Existing release preparation belongs to another tooling revision.')
    notes = args.notes_file.read_text() if args.notes_file else f'Vale {args.version}: compact native companion update.'
    policy().scan_bytes('release-notes.md', notes.encode())
    notes_file = work / 'release-notes.md'
    if notes_file.exists() and notes_file.read_text() != notes:
        fail('Release notes changed during an existing preparation.')
    notes_file.write_text(notes)
    if args.prepared_assets:
        manifest, info, source, assets = prepared_assets(args.prepared_assets.absolute(), args.version, output, head)
    else:
        if binding_path.exists():
            manifest, info, source, assets = prepared_assets(output, args.version, output, head)
        else:
            manifest, info, source, assets = build_assets(args.version, output)
            head = run('git', 'rev-parse', 'HEAD')
    if info['SUFeedURL'] != FEED or info['SURequireSignedFeed'] is not True:
        fail('The app must use the pinned signed production feed.')
    public_key = info['SUPublicEDKey']
    if len(base64.b64decode(public_key, validate=True)) != 32:
        fail('Invalid pinned Ed25519 public key.')
    old_feed = work / 'production-before.xml'
    if not old_feed.exists():
        download(FEED, old_feed)
    old_tree = feed_tree(old_feed, public_key)
    check_monotonic(old_tree, info['CFBundleVersion'])
    signer = Path(os.environ.get('VALE_SPARKLE_TOOLS_DIR', ROOT / '.build/artifacts/sparkle/Sparkle/bin')) / 'sign_update'
    if not signer.is_file():
        fail('Sparkle sign_update is unavailable; build normally or set VALE_SPARKLE_TOOLS_DIR to its bin directory.')
    archive = output / f'Vale-{args.version}-macOS-universal.zip'
    appcast = output / 'appcast.xml'
    if appcast.exists():
        verifier('feed', public_key, appcast)
        candidate = ET.fromstring(appcast.read_bytes()).find('./channel/item/enclosure')
        signature = candidate.get(f'{{{SPARKLE}}}edSignature')
    else:
        signature = run(signer, '--ed-key-file', seed, '-p', archive)
        verifier('archive', public_key, archive, signature)
        create_feed(old_tree, info, archive, signature, notes, appcast)
        run(signer, '--ed-key-file', seed, appcast)
    verifier('archive', public_key, archive, signature)
    verifier('feed', public_key, appcast)
    candidate_tree = ET.fromstring(appcast.read_bytes())
    candidate_item = candidate_tree.find('./channel/item')
    enclosure = candidate_item.find('enclosure')
    if (candidate_item.findtext(f'{{{SPARKLE}}}version') != info['CFBundleVersion']
            or candidate_item.findtext(f'{{{SPARKLE}}}shortVersionString') != args.version
            or enclosure.get('url') != f'https://github.com/{REPO}/releases/download/v{args.version}/{archive.name}'
            or enclosure.get('length') != str(archive.stat().st_size)
            or [ET.tostring(i) for i in candidate_tree.findall('./channel/item')[1:]]
                != [ET.tostring(i) for i in old_tree.findall('./channel/item')]):
        fail('Signed appcast does not bind the candidate or preserve the prior feed entries.')
    receipt = output / f'Vale-{args.version}-automatic-update.json'
    receipt_value = {'version': args.version, 'build': info['CFBundleVersion'], 'sourceCommit': source, 'toolingCommit': head,
        'archiveSHA256': sha(archive), 'archiveBytes': archive.stat().st_size, 'archiveEdSignature': signature,
        'appcastSHA256': sha(appcast), 'previousAppcastSHA256': sha(old_feed), 'publicKeySHA256': hashlib.sha256(base64.b64decode(public_key)).hexdigest(),
        'archiveAndFeedPublicKeyVerified': True, 'AppleSigning': manifest.get('signature'),
        'notarizationVerified': manifest.get('notarizationVerified') is True, 'genuineChatGPTVerified': manifest.get('genuineChatGPTVerified') is True,
        'releaseReady': manifest.get('releaseReady') is True,
        'supersedesPreparationDeliveryStatus': True,
        'boundary': 'Automatic update delivery acceptance is separate from product/provider/hardware acceptance. Original preparation-time manifests and setup README remain unchanged; this receipt and current release notes supersede their unpublished/preview-channel delivery status only.'}
    write_json(receipt, receipt_value)
    assets += [appcast, receipt]
    sums = output / f'Vale-{args.version}-update-SHA256SUMS.txt'
    sums.write_text(''.join(f'{sha(p)}  {p.name}\n' for p in assets))
    assets.append(sums)
    binding = {'version': args.version, 'toolingCommit': head, 'sourceCommit': source,
        'previousAppcastSHA256': sha(old_feed), 'notesSHA256': sha(notes_file),
        'files': {p.name: {'sha256': sha(p), 'bytes': p.stat().st_size} for p in assets}}
    if binding_path.exists() and json.loads(binding_path.read_text()) != binding:
        fail('Release preparation changed from its frozen binding.')
    write_json(binding_path, binding)
    if args.publish:
        remote = run('git', 'remote', 'get-url', 'origin')
        if remote not in (f'https://github.com/{REPO}.git', f'git@github.com:{REPO}.git', f'https://github.com/{REPO}'):
            fail('Unexpected Git remote.')
        # A normal Git push rejects non-fast-forward changes; never force-push or alter main implicitly.
        branch = run('git', 'symbolic-ref', '--short', 'HEAD')
        if branch in {'main', 'master'}:
            fail('Publish from a reviewed release branch; this command does not push main.')
        run('git', 'push', 'origin', f'HEAD:refs/heads/{branch}')
        remote_commit = json.loads(run('gh', 'api', f'repos/{REPO}/commits/{source}'))
        if remote_commit.get('sha') != source:
            fail('Push the reviewed source commit to origin before publishing.')
        publish('v' + args.version, source, assets, notes_file, sha(old_feed), work)
        write_json(work / 'publication.json', {**binding, 'published': True, 'productionFeedVerified': True,
            'releaseURL': f'https://github.com/{REPO}/releases/tag/v{args.version}'})
    print(json.dumps({'prepared': True, 'published': args.publish, 'version': args.version,
        'releaseURL': f'https://github.com/{REPO}/releases/tag/v{args.version}' if args.publish else None,
        'receipt': str(work / ('publication.json' if args.publish else 'release-binding.json'))}, indent=2))


if __name__ == '__main__':
    main()
