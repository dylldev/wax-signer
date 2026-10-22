"""Shared release metadata rules. No network or signing credentials are used here."""
import hashlib
import plistlib
import re
import struct
import zipfile
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit, urlunsplit


def base_url(value):
    u = urlsplit(value)
    if u.scheme != 'https' or not u.hostname or u.username or u.password or u.query or u.fragment:
        raise ValueError('base URL must be HTTPS with no credentials, query or fragment')
    path = unquote(u.path).rstrip('/')
    if any(p in ('.', '..') for p in path.split('/')):
        raise ValueError('base URL contains a relative path segment')
    return urlunsplit((u.scheme, u.netloc, quote(path, safe='/-._~'), '', ''))


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(256 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def metadata(path):
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if n.count('/') == 2 and n.startswith('Payload/') and n.endswith('.app/Info.plist')]
        if len(names) != 1: raise ValueError('IPA must contain one main app Info.plist')
        entry = z.getinfo(names[0])
        if entry.file_size > 1024 * 1024: raise ValueError('IPA Info.plist exceeds 1 MiB')
        info = plistlib.loads(z.read(entry))
        bad = z.testzip()
        if bad: raise ValueError('IPA ZIP integrity failed')
    if not isinstance(info, dict): raise ValueError('IPA Info.plist is not a dictionary')
    for k in ('CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion'):
        if not isinstance(info.get(k), str) or not info[k].strip(): raise ValueError('missing or invalid ' + k)
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', info['CFBundleIdentifier']): raise ValueError('invalid bundle identifier')
    if not isinstance(info.get('MinimumOSVersion', '17.0'), str): raise ValueError('invalid minimum OS version')
    return info


def opaque_icon(path):
    with open(path, 'rb') as f: header = f.read(33)
    if len(header) != 33 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('icon must be a PNG')
    w, h, depth, color = struct.unpack('>IIBB', header[16:26])
    if (w, h) != (1024, 1024) or color not in (0, 2): raise ValueError('icon must be 1024x1024 with no alpha channel')


def version_record(path, base, date):
    info = metadata(path)
    return info, dict(version=info['CFBundleShortVersionString'], buildVersion=info['CFBundleVersion'], date=date,
        downloadURL=base + '/' + quote(Path(path).name, safe=''), size=Path(path).stat().st_size,
        minOSVersion=info.get('MinimumOSVersion', '17.0'), sha256=digest(path),
        localizedDescription=f"Wax {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
