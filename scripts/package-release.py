#!/usr/bin/env python3
"""Package a locally verified release without publishing or including user data."""
from pathlib import Path
import hashlib,json,plistlib,platform,subprocess,zipfile
root=Path(__file__).resolve().parent.parent
app=root/'dist/Mythos.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
version=info['CFBundleShortVersionString']
def command(*args):
    return subprocess.check_output(args,cwd=root,text=True,stderr=subprocess.STDOUT).strip()
def digest(path):
    value=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1_048_576),b''):value.update(chunk)
    return value.hexdigest()
checks={}
for label,folder in [('native','native-ui-1.1-final'),('integration','integration-1.1-final')]:
    path=root/'artifacts'/folder/'results.json'
    values=json.loads(path.read_text())
    if not values or not all(value is True for value in values.values()):
        raise SystemExit(f'{label} verification has not passed: {path}')
    checks[label]={'passed':len(values),'results':values}
if '15/15 core checks passed' not in (root/'artifacts/unit-tests-1.1.log').read_text():
    raise SystemExit('Core verification has not passed.')
update_checks=json.loads((root/'artifacts/update-build-config-results.json').read_text())
if not update_checks or not all(value is True for value in update_checks.values()):
    raise SystemExit('Build-time updater configuration verification has not passed.')
command('codesign','--verify','--deep','--strict',str(app))
architectures=command('lipo','-archs',str(app/'Contents/MacOS/Lilt')).split()
if set(architectures)!={'x86_64','arm64'}:
    raise SystemExit('Build MYTHOS_ARCH=universal before packaging.')
release=root/'dist'/f'Mythos-{version}-macOS-universal.zip'
if release.exists(): release.unlink()
command('ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(release))
source=root/'dist'/f'Mythos-{version}-source-and-evidence.zip'
paths=command('git','ls-files','--cached','--others','--exclude-standard').splitlines()
prefix=f'Mythos-{version}-source/'
selected={
    'native-ui-1.1-final':['01-new-chat.png','02-capsule.png','03-attachments.png','04-PDF-preview.png','08-chat-history.png','09-settings-updates.png','09b-update-controls.png'],
    'integration-1.1-final':['07-real-general-reply.png','11-live-web-search.png']
}
with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED) as archive:
    for relative in paths:
        path=root/relative
        if path.is_file() and not relative.startswith(('artifacts/','dist/','.build','.git/')):
            archive.write(path,prefix+relative)
    for folder,names in selected.items():
        for name in names+['results.json']:
            path=root/'artifacts'/folder/name
            archive.write(path,prefix+'evidence/'+folder+'/'+name)
    for name in ['unit-tests-1.1.log','universal-build-1.1.log','update-build-config-results.json']:
        archive.write(root/'artifacts'/name,prefix+'evidence/'+name)
manifest={
    'product':info['CFBundleName'],'version':version,'build':info['CFBundleVersion'],
    'bundleIdentifier':info['CFBundleIdentifier'],'architectures':architectures,
    'minimumMacOS':info['LSMinimumSystemVersion'],'sourceCommit':command('git','rev-parse','HEAD'),
    'signature':'ad-hoc; strict deep verification passed','notarized':False,
    'updater':{'framework':'Sparkle 2.10.0','configured':bool(info.get('SUFeedURL') and info.get('SUPublicEDKey')),'signedFeedRequired':info['SURequireSignedFeed'],'verificationBeforeExtraction':info['SUVerifyUpdateBeforeExtraction'],'automaticChecks':False},
    'runtimeVerified':{'architecture':platform.machine(),'macOS':platform.mac_ver()[0]},
    'arm64RuntimeVerified':False,'laptopInstalled':False,
    'verification':{'corePassed':15,'updateBuildConfigPassed':len(update_checks),**checks},
    'files':[{ 'name':path.name,'bytes':path.stat().st_size,'sha256':digest(path)} for path in [release,source]],
    'remaining':['Screenshot delivery and laptop runtime verification','Existing private feed and trusted signing assets for live updates','Developer ID signing and notarization for distribution','First-use microphone and window-sharing consent']
}
manifest_path=root/'dist'/f'Mythos-{version}-release-manifest.json'
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
sums=root/'dist'/f'Mythos-{version}-SHA256SUMS.txt'
sums.write_text(''.join(f'{digest(path)}  {path.name}\n' for path in [release,source,manifest_path]))
print(json.dumps({'manifest':str(manifest_path),'archives':[str(release),str(source)],'checksums':str(sums)},indent=2))
