#!/usr/bin/env python3
"""Validate embedded updater metadata or embed explicitly supplied public configuration."""
import base64
import os
import plistlib
from pathlib import Path
import sys
import urllib.parse


def validate(feed, key):
    if not isinstance(feed, str) or not isinstance(key, str) or not feed or not key:
        raise SystemExit('Both an HTTPS feed and Ed25519 public key are required.')
    if any(character.isspace() for character in feed):
        raise SystemExit('The update feed must not contain whitespace.')
    try:
        url = urllib.parse.urlsplit(feed)
        port = url.port
    except ValueError:
        raise SystemExit('The update feed URL or port is invalid.')
    if url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None or url.fragment:
        raise SystemExit('The update feed must be HTTPS, without embedded credentials or fragments.')
    if port is not None and not 1 <= port <= 65535:
        raise SystemExit('The update feed port is invalid.')
    try:
        decoded = base64.b64decode(key, validate=True)
    except ValueError:
        raise SystemExit('The Ed25519 public key is not valid base64.')
    if len(decoded) != 32:
        raise SystemExit('The Ed25519 public key must decode to 32 bytes.')


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: configure-updates.py PATH_TO_INFO_PLIST')
    path = Path(sys.argv[1])
    with path.open('rb') as source:
        info = plistlib.load(source)
    feed = os.environ.get('VALE_UPDATE_FEED_URL', '')
    key = os.environ.get('VALE_UPDATE_PUBLIC_KEY', '')
    override = bool(feed or key)
    if override:
        validate(feed, key)
        info.update(
            SUFeedURL=feed, SUPublicEDKey=key,
            SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
            SUSignedFeedFailureExpirationInterval=0,
            SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True,
        )
        # Sparkle derives availability from automatic checking unless a custom override is needed.
        info.pop('SUAllowsAutomaticUpdates', None)
    else:
        feed, key = info.get('SUFeedURL'), info.get('SUPublicEDKey')
        if feed is None and key is None:
            return  # An unconfigured build remains inactive and byte-for-byte untouched.
        validate(feed, key)
        if (info.get('SURequireSignedFeed') is not True
                or info.get('SUVerifyUpdateBeforeExtraction') is not True
                or type(info.get('SUSignedFeedFailureExpirationInterval')) not in (int, float)
                or info['SUSignedFeedFailureExpirationInterval'] != 0):
            raise SystemExit('Configured updates require signed feeds, verification before extraction, and zero signed-feed failure expiration.')
    if override:
        # Validate first; invalid public input never modifies the bundle.
        with path.open('wb') as target:
            plistlib.dump(info, target)


if __name__ == '__main__':
    main()
