#!/usr/bin/env python3
"""Verify a downloaded release DMG, its checksum, and the publicly served Sparkle feed."""
import argparse
import base64
import hashlib
from pathlib import Path
import plistlib
import urllib.request
import xml.etree.ElementTree as ET
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

parser = argparse.ArgumentParser()
parser.add_argument('dmg', type=Path)
parser.add_argument('--info-plist', type=Path, default=Path('Resources/Info.plist'), help='Info.plist from the exact released revision')
args = parser.parse_args()
info = plistlib.loads(args.info_plist.read_bytes())
data = args.dmg.read_bytes()
expected_hash = Path(str(args.dmg) + '.sha256').read_text().split()[0]
actual_hash = hashlib.sha256(data).hexdigest()
assert actual_hash == expected_hash, 'Published checksum does not match downloaded DMG'
request = urllib.request.Request(info['SUFeedURL'], headers={'Cache-Control': 'no-cache'})
with urllib.request.urlopen(request, timeout=30) as response:
    feed = ET.fromstring(response.read(1024 * 1024))
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item = feed.find('channel/item')
assert item is not None, 'Published update feed is empty'
assert item.findtext('sparkle:version', namespaces=ns) == info['CFBundleVersion'], 'Feed build differs from released build'
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == info['CFBundleShortVersionString'], 'Feed version differs from released version'
enclosure = item.find('enclosure')
assert enclosure is not None
expected_url = f"https://github.com/Ninnja10563/Scribe/releases/download/v{info['CFBundleShortVersionString']}/{args.dmg.name}"
assert enclosure.get('url') == expected_url, 'Feed points to an unexpected release asset'
assert int(enclosure.get('length')) == len(data), 'Feed length differs from downloaded DMG'
key = Ed25519PublicKey.from_public_bytes(base64.b64decode(info['SUPublicEDKey'], validate=True))
signature = base64.b64decode(enclosure.get('{'+ns['sparkle']+'}edSignature'), validate=True)
key.verify(signature, data)
print(f"Verified Scribe {info['CFBundleShortVersionString']} build {info['CFBundleVersion']}: checksum, feed URL, size and Ed25519 signature")
print('SHA-256:', actual_hash)
