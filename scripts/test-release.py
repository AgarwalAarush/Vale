#!/usr/bin/env python3
"""Offline release-boundary tests. No production seed, network, app build or GUI."""
import hashlib
import base64
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('vale_release', ROOT / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)

FAKE_GH = '''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ['VALE_RELEASE_FIXTURE'])
args = sys.argv[1:]
with (root/'calls.jsonl').open('a') as stream: stream.write(json.dumps(args)+'\\n')
state_path = root/'state.json'
state = json.loads(state_path.read_text())
def save(): state_path.write_text(json.dumps(state))
if args[0] == 'api':
    if '/git/matching-refs/tags/' in args[-1]: print(json.dumps([{'ref':'refs/tags/v1.3.3', 'object':state['tag']}] if state['tag'] else []))
    elif '/git/tags/' in args[-1]: print(json.dumps(state['tag_objects'][args[-1].rsplit('/',1)[-1]]))
    elif '/releases?' in args[-1]: print(json.dumps([[state['release']] if state['release'] else []]))
    else: print(json.dumps({'private': False, 'owner': {'login': 'AgarwalAarush'}}))
elif args[:2] == ['release','create']:
    state['release'] = {'tag_name':args[2], 'draft':True, 'target_commitish':args[args.index('--target')+1], 'assets':[]}; save()
elif args[:2] == ['release','upload']:
    if os.environ.get('VALE_RELEASE_FAIL_UPLOAD'): sys.exit(31)
    source = pathlib.Path(args[3]); shutil.copyfile(source,root/'remote'/source.name)
    state['release']['assets'].append({'name': source.name}); save()
elif args[:2] == ['release','download']:
    name=args[args.index('--pattern')+1]; shutil.copyfile(root/'remote'/name,pathlib.Path(args[args.index('--dir')+1])/name)
    if os.environ.get('VALE_RELEASE_TAG_CHANGES'): state['tag']={'type':'commit','sha':'b'*40}; save()
elif args[:2] == ['release','edit']:
    state['release']['draft']=False
    if os.environ.get('VALE_RELEASE_BAD_PUBLIC_TAG'): state['tag']={'type':'commit','sha':'b'*40}
    elif state['tag'] is None: state['tag']={'type':'commit','sha':state['release']['target_commitish']}
    save()
else: sys.exit(32)
'''


class ReleaseTests(unittest.TestCase):
    def test_plan_is_offline_and_mutation_free(self):
        before = subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)
        result = subprocess.run([sys.executable, ROOT / 'scripts/release.py', '1.3.4', '--plan'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        value = json.loads(result.stdout)
        self.assertTrue(value['planOnly'])
        self.assertFalse(value['networkAccess'])
        self.assertEqual(before, subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT))

    def test_invalid_version_fails_before_any_work(self):
        result = subprocess.run([sys.executable, ROOT / 'scripts/release.py', '1.3.4;touch /tmp/nope', '--plan'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def publication_preflight_case(self, *, wrong_remote):
        def read_only_git(*args, env=None):
            if args == ('git', 'status', '--porcelain'):
                return ''
            if args == ('git', 'remote', 'get-url', 'origin'):
                return 'git@github.com:unrelated/other.git' if wrong_remote else f'git@github.com:{release.REPO}.git'
            if args == ('git', 'symbolic-ref', '--short', 'HEAD'):
                return 'main'
            self.fail('Preflight unexpectedly reached additional work: ' + repr(args))
        with patch.object(sys, 'argv', ['release.py', '1.3.4', '--publish']), \
                patch.object(release, 'run', side_effect=read_only_git), \
                patch.object(release, 'key_path') as key, patch.object(release, 'build_assets') as build:
            with self.assertRaises(SystemExit):
                release.main()
            key.assert_not_called()
            build.assert_not_called()

    def test_wrong_remote_preflight_precedes_signing_or_build(self):
        self.publication_preflight_case(wrong_remote=True)

    def test_main_branch_preflight_precedes_signing_or_build(self):
        self.publication_preflight_case(wrong_remote=False)

    def test_seed_metadata_only_requires_private_owned_file_and_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary).resolve()
            directory.chmod(0o700)
            seed = directory / 'fixture.key'
            seed.touch(mode=0o600)
            with patch.dict(os.environ, {'VALE_UPDATE_SIGNING_KEY_FILE': str(seed)}), patch.object(release, 'run', return_value=str(directory)):
                self.assertEqual(release.key_path(), seed)
                seed.chmod(0o644)
                with self.assertRaises(SystemExit):
                    release.key_path()
                seed.chmod(0o600)
                directory.chmod(0o755)
                with self.assertRaises(SystemExit):
                    release.key_path()
                directory.chmod(0o700)
                alias = directory / 'alias.key'
                alias.symlink_to(seed)
                with patch.dict(os.environ, {'VALE_UPDATE_SIGNING_KEY_FILE': str(alias)}):
                    with self.assertRaises(SystemExit):
                        release.key_path()

    def test_monotonic_feed_preserves_prior_items(self):
        tree = ET.fromstring(f'<rss><channel><title>Vale</title><item><title>Old</title><enclosure sparkle:version="9" xmlns:sparkle="{release.SPARKLE}"/></item></channel></rss>')
        for bad in ('8', '9', '9.0'):
            with self.assertRaises(SystemExit):
                release.check_monotonic(tree, bad)
        original = ET.tostring(tree.find('./channel/item'))
        original_tree = ET.tostring(tree)
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'Vale-1.3.3-macOS-universal.zip'
            archive.write_bytes(b'generated archive')
            output = Path(folder) / 'appcast.xml'
            release.create_feed(tree, {'CFBundleVersion': '10', 'CFBundleShortVersionString': '1.3.3', 'LSMinimumSystemVersion': '14.0'}, archive, 'PUBLIC_SIGNATURE', '<b>plain text</b>', output)
            result = ET.fromstring(output.read_bytes())
            items = result.findall('./channel/item')
            self.assertEqual(len(items), 2)
            self.assertEqual(ET.tostring(items[1]), original)
            self.assertEqual(ET.tostring(tree), original_tree)
            self.assertEqual(items[0].findtext('description'), '<b>plain text</b>')
            self.assertEqual(items[0].find('enclosure').get('url'), f'https://github.com/{release.REPO}/releases/download/v1.3.3/{archive.name}')

    def test_fresh_prepare_orchestrates_signing_and_compares_unmodified_prior_feed(self):
        """Exercise main's fresh-feed branch; only external Git/signature/prepared-app boundaries are fixtures."""
        with tempfile.TemporaryDirectory() as temporary:
            fixture = Path(temporary)
            common = fixture / 'common'
            common.mkdir()
            tools = fixture / 'bin'
            tools.mkdir()
            signer = tools / 'sign_update'
            signer.touch()
            seed = fixture / 'empty-fixture-seed.key'
            seed.touch(mode=0o600)
            original = fixture / 'reviewed-assets'
            original.mkdir()
            source = 'a' * 40
            head = 'b' * 40
            public = base64.b64encode(bytes(32)).decode()
            signature = base64.b64encode(bytes(64)).decode()
            old_feed = f'<rss xmlns:sparkle="{release.SPARKLE}"><channel><title>Vale</title><item><title>Vale1.3.0</title><sparkle:version>7</sparkle:version><enclosure url="https://github.com/{release.REPO}/releases/download/v1.3.0/old.zip" /></item></channel></rss>'.encode()
            commands = []

            def fixture_run(*arguments, env=None):
                args = tuple(str(a) for a in arguments)
                commands.append(args)
                if args == ('git', 'status', '--porcelain'):
                    return ''
                if args == ('git', 'rev-parse', 'HEAD'):
                    return head
                if args == ('git', 'rev-parse', '--git-common-dir'):
                    return str(common)
                if args == (str(signer), '--ed-key-file', str(seed), '-p', str(common / 'codex-factory/releases/v1.3.3/assets/Vale-1.3.3-macOS-universal.zip')):
                    return signature
                if args[:3] == (str(signer), '--ed-key-file', str(seed)) and len(args) == 4:
                    feed = Path(args[-1])
                    content = feed.read_bytes()
                    feed.write_bytes(content + f'<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(content)}\n-->\n'.encode())
                    return ''
                self.fail('Fresh preparation reached an unexpected external action: ' + repr(args))

            def fixture_prepared(folder, version, output, tooling_head):
                self.assertEqual(folder, original)
                self.assertEqual(tooling_head, head)
                assets = []
                for suffix in ('macOS-universal.zip', 'source-and-evidence.zip', 'laptop-setup.zip', 'laptop-setup.dmg', 'release-manifest.json', 'SHA256SUMS.txt'):
                    path = output / f'Vale-{version}-{suffix}'
                    path.write_bytes(('generated immutable ' + suffix).encode())
                    assets.append(path)
                return ({'signature': {'kind': 'ad-hoc'}, 'releaseReady': False, 'genuineChatGPTVerified': False},
                        {'CFBundleVersion': '10', 'CFBundleShortVersionString': version, 'LSMinimumSystemVersion': '14.0',
                         'SUFeedURL': release.FEED, 'SURequireSignedFeed': True, 'SUPublicEDKey': public}, source, assets)

            def fixture_download(url, target):
                self.assertEqual(url, release.FEED)
                target.write_bytes(old_feed)

            with patch.object(sys, 'argv', ['release.py', '1.3.3', '--prepare-only', '--prepared-assets', str(original)]), \
                    patch.dict(os.environ, {'VALE_SPARKLE_TOOLS_DIR': str(tools)}), \
                    patch.object(release, 'key_path', return_value=seed), \
                    patch.object(release, 'run', side_effect=fixture_run), \
                    patch.object(release, 'prepared_assets', side_effect=fixture_prepared), \
                    patch.object(release, 'download', side_effect=fixture_download), \
                    patch.object(release, 'verifier') as verify, contextlib.redirect_stdout(io.StringIO()) as stdout:
                release.main()
            work = common / 'codex-factory/releases/v1.3.3'
            result = json.loads(stdout.getvalue())
            self.assertTrue(result['prepared'])
            self.assertFalse(result['published'])
            self.assertEqual((work / 'production-before.xml').read_bytes(), old_feed)
            entries = ET.fromstring((work / 'assets/appcast.xml').read_bytes()).findall('./channel/item')
            self.assertEqual(len(entries), 2)
            self.assertEqual(entries[0].findtext(f'{{{release.SPARKLE}}}version'), '10')
            self.assertEqual(entries[1].findtext(f'{{{release.SPARKLE}}}version'), '7')
            binding = json.loads((work / 'release-binding.json').read_text())
            self.assertEqual(binding['sourceCommit'], source)
            self.assertEqual(len(binding['files']), 9)
            signing = [args for args in commands if args[0] == str(signer)]
            self.assertEqual(len(signing), 2)
            self.assertIn('-p', signing[0])
            self.assertTrue(signing[1][-1].endswith('/assets/appcast.xml'))
            self.assertEqual(verify.call_count, 4)
            self.assertFalse((work / 'publication.json').exists())

    def native_clone_case(self, *, instruction_tamper=False):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            app = folder / 'production/Vale.app'
            (app / 'Contents/MacOS').mkdir(parents=True)
            original_info = {'CFBundleIdentifier': 'local.lilt.companion', 'CFBundleExecutable': 'Lilt', 'CFBundleVersion': '10'}
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(original_info))
            (app / 'Contents/MacOS/Lilt').write_bytes(b'generated executable fixture')
            original_tree = release.tree_digest(app)
            calls = []

            def fixture_run(*arguments, env=None):
                args = [str(a) for a in arguments]
                calls.append(args)
                if args[0] == '/usr/bin/ditto':
                    shutil.copytree(args[1], args[2])
                if args[0] == '/usr/bin/otool':
                    changed = instruction_tamper and Path(args[-1]) != app / 'Contents/MacOS/Lilt'
                    return '0000000100001000 ' + ('deadbeef' if changed else 'aabbccdd')
                if '--self-test' in args:
                    executable = Path(args[args.index('--self-test') - 1])
                    self.assertNotEqual(executable, app / 'Contents/MacOS/Lilt')
                    clone_info = plistlib.loads((executable.parent.parent / 'Info.plist').read_bytes())
                    self.assertTrue(clone_info['CFBundleIdentifier'].startswith('local.vale.releasetest.'))
                    self.assertEqual({k: v for k, v in clone_info.items() if k != 'CFBundleIdentifier'},
                                     {k: v for k, v in original_info.items() if k != 'CFBundleIdentifier'})
                return ''

            with patch.object(release, 'run', side_effect=fixture_run):
                if instruction_tamper:
                    with self.assertRaises(SystemExit):
                        release.isolated_native_check(app, folder / 'evidence', {})
                else:
                    receipt = release.isolated_native_check(app, folder / 'evidence', {})
                    self.assertTrue(receipt['productionAppUnchanged'])
            spawned = [args for args in calls if '--self-test' in args]
            self.assertEqual(len(spawned), 0 if instruction_tamper else 1)
            if spawned:
                self.assertEqual(Path(spawned[0][1]), ROOT / 'scripts/run-bounded.py')
                signature_checks = [i for i, args in enumerate(calls) if args[:4] == ['/usr/bin/codesign', '--verify', '--deep', '--strict']]
                self.assertEqual(len(signature_checks), 1)
                self.assertLess(signature_checks[0], calls.index(spawned[0]))
            self.assertEqual(release.tree_digest(app), original_tree)

    def test_native_checks_execute_only_nonce_clone_after_strict_verification(self):
        self.native_clone_case()

    def test_changed_clone_instruction_sections_prevent_any_native_execution(self):
        self.native_clone_case(instruction_tamper=True)

    def publication_case(self, *, fail_upload=False, changed_feed=False, existing_public=False, mismatch=False,
                         wrong_tag=False, annotated=False, bad_peel=False, deep_peel=False,
                         changing_tag=False, bad_public_tag=False, fail_public_download=False):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / 'remote').mkdir()
            (folder / 'bin').mkdir()
            work = folder / 'work'
            asset_folder = work / 'assets'
            asset_folder.mkdir(parents=True)
            command = folder / 'bin/gh'
            command.write_text(FAKE_GH)
            command.chmod(0o755)
            source = 'a' * 40
            state = {'release': {'tag_name': 'v1.3.3', 'draft': not existing_public, 'target_commitish': source, 'assets': []} if existing_public or mismatch else None,
                     'tag': {'type': 'commit', 'sha': 'b' * 40} if wrong_tag else None, 'tag_objects': {}}
            if annotated or bad_peel or deep_peel:
                ids = [f'{n:040x}' for n in range(1, 11)]
                state['tag'] = {'type': 'tag', 'sha': ids[0]}
                count = 9 if deep_peel else 2
                for index in range(count):
                    state['tag_objects'][ids[index]] = {'sha': ids[index], 'object':
                        {'type': 'tag', 'sha': ids[index + 1]} if index < count - 1 else {'type': 'commit', 'sha': source}}
                if bad_peel:
                    state['tag_objects'][ids[0]]['sha'] = ids[1]
            assets = []
            for name, contents in [('app.zip', b'app-generated'), ('appcast.xml', b'candidate-feed-generated')]:
                path = asset_folder / name
                path.write_bytes(contents)
                assets.append(path)
            if mismatch:
                state['release']['assets'] = [{'name': 'app.zip'}]
                (folder / 'remote/app.zip').write_bytes(b'changed-upload')
            (folder / 'state.json').write_text(json.dumps(state))
            notes = work / 'notes.md'
            notes.write_text('Generated fixture release')
            release.write_json(work / 'release-binding.json', {'sourceCommit': source, 'version': '1.3.3',
                'files': {p.name: {'sha256': release.sha(p), 'bytes': p.stat().st_size} for p in assets}})
            old_hash = hashlib.sha256(b'old-feed-generated').hexdigest()

            def generated_download(url, destination):
                if url == release.FEED:
                    published = json.loads((folder / 'state.json').read_text())['release']
                    if published is not None and not published['draft']:
                        destination.write_bytes(b'candidate-feed-generated')
                    else:
                        destination.write_bytes(b'changed-feed' if changed_feed else b'old-feed-generated')
                else:
                    if fail_public_download:
                        raise SystemExit('private-tool-output-should-not-escape')
                    shutil.copyfile(folder / 'remote' / url.rsplit('/', 1)[-1], destination)

            environment = {'PATH': str(folder / 'bin') + os.pathsep + os.environ['PATH'], 'VALE_RELEASE_FIXTURE': str(folder)}
            if fail_upload:
                environment['VALE_RELEASE_FAIL_UPLOAD'] = 'yes'
            if changing_tag:
                environment['VALE_RELEASE_TAG_CHANGES'] = 'yes'
            if bad_public_tag:
                environment['VALE_RELEASE_BAD_PUBLIC_TAG'] = 'yes'
            before_failure = fail_upload or changed_feed or existing_public or mismatch or wrong_tag or bad_peel or deep_peel or changing_tag
            after_failure = bad_public_tag or fail_public_download
            with patch.dict(os.environ, environment), patch.object(release, 'download', side_effect=generated_download):
                if before_failure or after_failure:
                    with self.assertRaises(SystemExit) as error:
                        release.publish('v1.3.3', source, assets, notes, old_hash, work)
                    if after_failure:
                        self.assertIn('ALREADY PUBLIC: v1.3.3', str(error.exception))
                        self.assertIn('https://github.com/AgarwalAarush/Vale/releases/tag/v1.3.3', str(error.exception))
                        self.assertIn(str(work / 'release-binding.json'), str(error.exception))
                        self.assertNotIn('private-tool-output-should-not-escape', str(error.exception))
                else:
                    release.publish('v1.3.3', source, assets, notes, old_hash, work)
                    receipt = json.loads((work / 'publication.json').read_text())
                    self.assertTrue(receipt['published'])
                    self.assertTrue(receipt['productionFeedVerified'])
                    self.assertEqual(receipt['tagCommitVerified'], source)
                    self.assertFalse((work / 'appcast.xml').exists())
            calls = [json.loads(line) for line in (folder / 'calls.jsonl').read_text().splitlines()]
            promoted = any(call[:2] == ['release', 'edit'] for call in calls)
            self.assertEqual(promoted, not before_failure)
            if promoted:
                edit_index = next(index for index, call in enumerate(calls) if call[:2] == ['release', 'edit'])
                self.assertEqual(sum(call[:2] == ['release', 'download'] for call in calls[:edit_index]), len(assets))
            if wrong_tag or bad_peel or deep_peel:
                self.assertFalse(any(call[:2] == ['release', 'create'] for call in calls))
            self.assertFalse(any('force' in value or 'retag' in value for call in calls for value in call))

    def test_draft_upload_failure_never_promotes(self):
        self.publication_case(fail_upload=True)

    def test_changed_production_feed_never_promotes(self):
        self.publication_case(changed_feed=True)

    def test_public_version_is_immutable(self):
        self.publication_case(existing_public=True)

    def test_changed_draft_asset_never_promotes(self):
        self.publication_case(mismatch=True)

    def test_complete_draft_verified_before_promotion(self):
        self.publication_case()

    def test_conflicting_lightweight_tag_prevents_draft_creation(self):
        self.publication_case(wrong_tag=True)

    def test_recursively_peeled_annotated_tag_matches_source(self):
        self.publication_case(annotated=True)

    def test_mismatched_annotated_object_is_rejected(self):
        self.publication_case(bad_peel=True)

    def test_excessively_deep_annotated_tag_is_rejected(self):
        self.publication_case(deep_peel=True)

    def test_tag_changed_after_upload_prevents_promotion(self):
        self.publication_case(changing_tag=True)

    def test_post_publication_tag_mismatch_reports_public_release_and_binding(self):
        self.publication_case(bad_public_tag=True)

    def test_failed_anonymous_download_reports_already_public_and_binding(self):
        self.publication_case(fail_public_download=True)

    def test_public_only_crypto_verifier_rejects_tampering(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            fixture = folder / 'fixture.swift'
            fixture.write_text('''import CryptoKit
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
let archive = Data("generated archive".utf8)
try archive.write(to: root.appendingPathComponent("archive.zip"))
let content = Data("<rss><channel/></rss>\\n".utf8)
let sig = try key.signature(for: content).base64EncodedString()
let footer = "<!-- sparkle-signatures:\\nedSignature: \\(sig)\\nlength: \\(content.count)\\n-->\\n"
try (content + Data(footer.utf8)).write(to: root.appendingPathComponent("feed.xml"))
print(key.publicKey.rawRepresentation.base64EncodedString())
print(try key.signature(for: archive).base64EncodedString())
''')
            environment = os.environ.copy()
            sdk = Path('/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk')
            if sdk.exists():
                environment['SDKROOT'] = str(sdk)
            environment['CLANG_MODULE_CACHE_PATH'] = str(folder / 'module-cache')
            generated = subprocess.run(['swift', str(fixture), str(folder)], env=environment, capture_output=True, text=True)
            self.assertEqual(generated.returncode, 0, generated.stderr)
            key, signature = generated.stdout.splitlines()

            def verify(mode, path, sig=None):
                command = ['swift', str(ROOT / 'scripts/verify-release-signatures.swift'), mode, key, str(path)]
                return subprocess.run(command + ([sig] if sig else []), env=environment, capture_output=True)

            archive = folder / 'archive.zip'
            feed = folder / 'feed.xml'
            self.assertEqual(verify('archive', archive, signature).returncode, 0)
            self.assertEqual(verify('feed', feed).returncode, 0)
            with patch.dict(os.environ, {'SDKROOT': '/nonexistent/stale-sdk'}):
                release.verifier('feed', key, feed)
            archive.write_bytes(b'tampered')
            self.assertNotEqual(verify('archive', archive, signature).returncode, 0)
            original = feed.read_bytes()
            feed.write_bytes(original.replace(b'<channel/>', b'<changed/>'))
            self.assertNotEqual(verify('feed', feed).returncode, 0)
            feed.write_bytes(original.replace(b'length: ', b'length: 9'))
            self.assertNotEqual(verify('feed', feed).returncode, 0)
            feed.write_bytes(original + b'unsigned trailing bytes')
            self.assertNotEqual(verify('feed', feed).returncode, 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
