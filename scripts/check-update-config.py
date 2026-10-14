#!/usr/bin/env python3
"""Exercise the build-time updater gate with public fixtures; never use signing credentials."""
from pathlib import Path
import json,os,plistlib,subprocess,sys,tempfile
root=Path(__file__).resolve().parent.parent
key='pfIShU4dEXqPd5ObYNfDBiQWcXozk7estwzTnF9BamQ='
cases=[('inactive',None,None,True),('configured','https://private.example.invalid/appcast.xml',key,True),('missing key','https://private.example.invalid/appcast.xml',None,False),('insecure feed','http://private.example.invalid/appcast.xml',key,False),('invalid key','https://private.example.invalid/appcast.xml','bad',False)]
results={}
(root/'artifacts').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=root/'artifacts') as directory:
    for name,feed,public,expected in cases:
        path=Path(directory)/'Info.plist';path.write_bytes(plistlib.dumps({'CFBundleName':'Fixture'}));original=path.read_bytes()
        env=os.environ.copy();env.pop('VALE_UPDATE_FEED_URL',None);env.pop('VALE_UPDATE_PUBLIC_KEY',None)
        if feed is not None:env['VALE_UPDATE_FEED_URL']=feed
        if public is not None:env['VALE_UPDATE_PUBLIC_KEY']=public
        process=subprocess.run([sys.executable,str(root/'scripts/configure-updates.py'),str(path)],env=env,capture_output=True)
        results[name]=(process.returncode==0)==expected
        if not expected or name=='inactive':results[name]=results[name] and path.read_bytes()==original
        if name=='configured':
            info=plistlib.loads(path.read_bytes());results[name]=results[name] and info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction'] and not info['SUEnableAutomaticChecks']
(root/'artifacts/update-build-config-results.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results));sys.exit(0 if all(results.values()) else 1)
