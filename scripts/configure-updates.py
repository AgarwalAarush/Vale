#!/usr/bin/env python3
"""Embed only explicitly supplied existing public updater configuration. Never generate keys."""
import base64,os,plistlib,sys,urllib.parse
feed=os.environ.get('VALE_UPDATE_FEED_URL','')
key=os.environ.get('VALE_UPDATE_PUBLIC_KEY','')
if not feed and not key:
    sys.exit(0)
if not feed or not key:
    raise SystemExit('Both an existing HTTPS feed and existing Ed25519 public key are required.')
u=urllib.parse.urlsplit(feed)
if u.scheme!='https' or not u.hostname or u.username or u.password or u.fragment:
    raise SystemExit('The update feed must be HTTPS, without embedded credentials or fragments.')
try:
    decoded=base64.b64decode(key,validate=True)
except ValueError:
    raise SystemExit('The existing Ed25519 public key is not valid base64.')
if len(decoded)!=32:
    raise SystemExit('The existing Ed25519 public key must decode to 32 bytes.')
with open(sys.argv[1],'rb') as f: info=plistlib.load(f)
info.update(SUFeedURL=feed,SUPublicEDKey=key,SURequireSignedFeed=True,SUVerifyUpdateBeforeExtraction=True,SUEnableAutomaticChecks=False,SUAutomaticallyUpdate=False,SUAllowsAutomaticUpdates=False)
with open(sys.argv[1],'wb') as f: plistlib.dump(info,f)
