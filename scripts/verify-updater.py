#!/usr/bin/env python3
"""Exercise Sparkle's real installer on disposable app copies and reject a forged signature."""
import base64
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import shutil
import subprocess
import threading
import urllib.request
import xml.etree.ElementTree as ET
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

root = Path('build/update-test').resolve(); root.mkdir(parents=True, exist_ok=True)
source = Path('build/Scribe.app').resolve()
framework = source / 'Contents/Frameworks'
cli = root / 'SparkleValidation.app'
(cli / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(cli / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.scribe.UpdateValidation','CFBundleExecutable':'sparkle','CFBundlePackageType':'APPL','CFBundleVersion':'1','NSPrincipalClass':'NSApplication'}))
subprocess.run(['ditto',str(framework),str(cli/'Contents/Frameworks')],check=True)
headers = root / 'include/Sparkle'; headers.mkdir(parents=True,exist_ok=True)
base = 'https://raw.githubusercontent.com/sparkle-project/Sparkle/2.10.0/'
for name in ['main.m','SPUCommandLineDriver.m','SPUCommandLineDriver.h','SPUCommandLineUserDriver.m','SPUCommandLineUserDriver.h']:
    (root/name).write_bytes(urllib.request.urlopen(base+'sparkle-cli/'+name,timeout=30).read())
for path in ['InstallerLauncher/SUInstallerLauncher+Private.h','Sparkle/SPUUserAgent+Private.h']:
    (headers/Path(path).name).write_bytes(urllib.request.urlopen(base+path,timeout=30).read())
subprocess.run(['xcrun','clang','-fobjc-arc','-fmodules','-DSPU_OBJC_DIRECT=','-DSPU_OBJC_DIRECT_MEMBERS=','-I',str(root/'include'),'-F',str(framework),'-framework','Sparkle','-framework','Cocoa','-Wl,-rpath,@executable_path/../Frameworks',*[str(root/name) for name in ['main.m','SPUCommandLineDriver.m','SPUCommandLineUserDriver.m']],'-o',str(cli/'Contents/MacOS/sparkle')],check=True)
subprocess.run(['codesign','--force','--deep','--sign','-',str(cli)],check=True)
key=Ed25519PrivateKey.generate()
public=base64.b64encode(key.public_key().public_bytes_raw()).decode()
old=root/'installed/Scribe.app'; new=root/'payload/Scribe.app'
for app in [old,new]:
    subprocess.run(['ditto',str(source),str(app)],check=True)
    path=app/'Contents/Info.plist'; info=plistlib.loads(path.read_bytes()); info['SUPublicEDKey']=public
    if app==old: info['CFBundleVersion']='1'
    path.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
version=plistlib.loads((new/'Contents/Info.plist').read_bytes())['CFBundleVersion']
archive=root/'update.dmg'
subprocess.run(['hdiutil','create','-volname','Scribe Update Test','-srcfolder',str(new.parent),'-ov','-format','UDZO',str(archive)],check=True)
server=ThreadingHTTPServer(('127.0.0.1',0),partial(SimpleHTTPRequestHandler,directory=str(root)))
threading.Thread(target=server.serve_forever,daemon=True).start()
url=f'http://127.0.0.1:{server.server_port}'
ns='http://www.andymatuschak.org/xml-namespaces/sparkle'; ET.register_namespace('sparkle',ns)
def feed(signature):
    rss=ET.Element('rss',version='2.0'); channel=ET.SubElement(rss,'channel'); ET.SubElement(channel,'title').text='Update test'
    item=ET.SubElement(channel,'item'); ET.SubElement(item,'title').text='Scribe test update'
    ET.SubElement(item,'{'+ns+'}version').text=version
    ET.SubElement(item,'enclosure',{'url':url+'/update.dmg','length':str(archive.stat().st_size),'type':'application/octet-stream','{'+ns+'}edSignature':base64.b64encode(signature).decode()})
    (root/'appcast.xml').write_bytes(ET.tostring(rss,encoding='utf-8',xml_declaration=True))
def install(label):
    with (root/(label+'.log')).open('w') as log:
        return subprocess.run([str(cli/'Contents/MacOS/sparkle'),str(old),'--check-immediately','--feed-url',url+'/appcast.xml?test='+label,'--user-agent-name','Scribe CI','--verbose'],stdout=log,stderr=subprocess.STDOUT,timeout=150).returncode
try:
    feed(Ed25519PrivateKey.generate().sign(archive.read_bytes()))
    assert install('invalid-signature') != 0, 'Forged update was accepted'
    assert plistlib.loads((old/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='1', 'Failed update changed installed app'
    feed(key.sign(archive.read_bytes()))
    assert install('valid-signature') == 0, 'Valid signed update failed'
    assert plistlib.loads((old/'Contents/Info.plist').read_bytes())['CFBundleVersion']==version
    assert hashlib.sha256((old/'Contents/MacOS/Scribe').read_bytes()).digest()==hashlib.sha256((new/'Contents/MacOS/Scribe').read_bytes()).digest()
    subprocess.run(['codesign','--verify','--deep','--strict',str(old)],check=True)
    subprocess.run(['python3','scripts/native-smoke.py',str(old/'Contents/MacOS/Scribe'),'--startup-smoke-test'],check=True)
    print('Rejected forged update; installed authentic DMG; verified installed signature, executable and startup.')
finally:
    server.shutdown()
