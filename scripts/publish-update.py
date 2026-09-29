#!/usr/bin/env python3
"""Sign a published DMG and atomically advance Scribe's Sparkle feed."""
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

repo = 'Ninnja10563/Scribe'
info = plistlib.loads(Path('Resources/Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
tag = 'v' + version
assert os.environ['GITHUB_REF_NAME'] == tag, 'Tag and bundle version must match'
dmg = Path('build') / f'Scribe-{version}-arm64.dmg'
key = Ed25519PrivateKey.from_private_bytes(base64.b64decode(os.environ['SCRIBE_UPDATE_PRIVATE_KEY'], validate=True))
assert base64.b64encode(key.public_key().public_bytes_raw()).decode() == info['SUPublicEDKey'], 'Signing key does not match application'
signature = key.sign(dmg.read_bytes())
key.public_key().verify(signature, dmg.read_bytes())
# Publication must exist before clients can discover this update.
release = json.loads(subprocess.check_output(['gh', 'release', 'view', tag, '--repo', repo, '--json', 'assets,isDraft']))
assert not release['isDraft'] and any(asset['name'] == dmg.name for asset in release['assets'])
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
root = ET.Element('rss', version='2.0'); channel = ET.SubElement(root, 'channel')
ET.SubElement(channel, 'title').text = 'Scribe Updates'
item = ET.SubElement(channel, 'item'); ET.SubElement(item, 'title').text = 'Scribe ' + version
ET.SubElement(item, '{'+namespace+'}version').text = build
ET.SubElement(item, '{'+namespace+'}shortVersionString').text = version
ET.SubElement(item, '{'+namespace+'}minimumSystemVersion').text = info['LSMinimumSystemVersion']
ET.SubElement(item, 'description').text = 'This Scribe development update includes tested fixes and improvements. See the GitHub release for details.'
ET.SubElement(item, '{'+namespace+'}releaseNotesLink').text = f'https://github.com/{repo}/releases/tag/{tag}'
ET.SubElement(item, 'enclosure', {'url': f'https://github.com/{repo}/releases/download/{tag}/{dmg.name}', 'length': str(dmg.stat().st_size), 'type': 'application/octet-stream', '{'+namespace+'}edSignature': base64.b64encode(signature).decode()})
xml = ET.tostring(root, encoding='utf-8', xml_declaration=True)
current = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/contents/appcast.xml?ref=updates']))
old = ET.fromstring(base64.b64decode(current['content']))
for node in old.iter('{'+namespace+'}version'):
    assert int(node.text) <= int(build), 'Refusing to downgrade the update feed'
request = {'message': f'Publish signed Scribe {version} update', 'branch': 'updates', 'sha': current['sha'], 'content': base64.b64encode(xml).decode()}
subprocess.run(['gh', 'api', '--method', 'PUT', f'repos/{repo}/contents/appcast.xml', '--input', '-'], input=json.dumps(request).encode(), stdout=subprocess.DEVNULL, check=True)
print(f'Published signed update feed for {version} (build {build})')
