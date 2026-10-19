#!/usr/bin/env python3
"""Exercise build-time updater defaults and fail-closed gates with public fixtures."""
from pathlib import Path
import json
import os
import plistlib
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parent.parent
key = 'pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ='
secure = dict(
    CFBundleName='Fixture', SUFeedURL='https://github.com/fixture/project/releases/latest/download/appcast.xml',
    SUPublicEDKey=key, SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
    SUSignedFeedFailureExpirationInterval=0, SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True,
)
cases = [
    ('inactive', {}, None, None, True),
    ('configured defaults', {'SUAllowsAutomaticUpdates': False}, secure['SUFeedURL'], key, True),
    ('embedded configuration', secure, None, None, True),
    ('missing key', {}, secure['SUFeedURL'], None, False),
    ('insecure feed', {}, 'http://example.invalid/appcast.xml', key, False),
    ('invalid key', {}, secure['SUFeedURL'], 'bad', False),
    ('credentials in feed', {}, 'https://user:secret@example.invalid/appcast.xml', key, False),
    ('fragment in feed', {}, 'https://example.invalid/appcast.xml#other', key, False),
    ('invalid port', {}, 'https://example.invalid:wrong/appcast.xml', key, False),
    ('embedded unsigned feed', dict(secure, SURequireSignedFeed=False), None, None, False),
    ('embedded delayed trust fallback', dict(secure, SUSignedFeedFailureExpirationInterval=1728000), None, None, False),
    ('embedded missing expiration', {k:v for k,v in secure.items() if k != 'SUSignedFeedFailureExpirationInterval'}, None, None, False),
    ('embedded partial configuration', {'SUFeedURL': secure['SUFeedURL']}, None, None, False),
]
results = {}
(root / 'artifacts').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=root / 'artifacts') as directory:
    for name, base, feed, public, expected in cases:
        path = Path(directory) / 'Info.plist'
        path.write_bytes(plistlib.dumps(dict(CFBundleName='Fixture', **{k:v for k,v in base.items() if k != 'CFBundleName'})))
        original = path.read_bytes()
        env = os.environ.copy()
        env.pop('VALE_UPDATE_FEED_URL', None)
        env.pop('VALE_UPDATE_PUBLIC_KEY', None)
        if feed is not None:
            env['VALE_UPDATE_FEED_URL'] = feed
        if public is not None:
            env['VALE_UPDATE_PUBLIC_KEY'] = public
        process = subprocess.run([sys.executable, str(root / 'scripts/configure-updates.py'), str(path)], env=env, capture_output=True)
        results[name] = (process.returncode == 0) == expected
        if not expected or feed is None:
            results[name] = results[name] and path.read_bytes() == original
        if name == 'configured defaults' and process.returncode == 0:
            info = plistlib.loads(path.read_bytes())
            results[name] = results[name] and all(info.get(flag) is True for flag in (
                'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction', 'SUEnableAutomaticChecks', 'SUAutomaticallyUpdate'
            )) and info['SUSignedFeedFailureExpirationInterval'] == 0 and 'SUAllowsAutomaticUpdates' not in info
(root / 'artifacts/update-build-config-results.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results))
sys.exit(0 if all(results.values()) else 1)
