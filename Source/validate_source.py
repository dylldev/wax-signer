#!/usr/bin/env python3
"""Validate a release feed and its actual staged/downloaded artifacts. No publishing."""
import argparse
import json
import os
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import unquote, urlsplit
from source_artifact import digest, metadata, opaque_icon


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('url', nargs='?')
    ap.add_argument('--dir'); ap.add_argument('--expect-base')
    a = ap.parse_args()
    if not a.url and not (a.dir and a.expect_base): ap.error('provide URL or --dir with --expect-base')
    base = (a.expect_base or '').rstrip('/')
    failures = []
    referenced = set()
    def check(ok, message):
        print(('ok    ' if ok else 'FAIL  ') + message)
        if not ok: failures.append(message)
        return ok
    with tempfile.TemporaryDirectory() as work:
        def get(url, limit):
            if not isinstance(url, str): return 0, None
            u = urlsplit(url)
            if u.query or u.fragment: return 0, None
            if a.dir:
                b = urlsplit(base); prefix = b.path.rstrip('/') + '/'
                if (u.scheme, u.netloc) != (b.scheme, b.netloc) or not u.path.startswith(prefix): return 0, None
                relative = unquote(u.path[len(prefix):])
                if any(p in ('', '.', '..') for p in relative.split('/')): return 0, None
                path = Path(a.dir) / relative
                if path.is_symlink() or Path(a.dir).resolve() not in path.resolve().parents: return 0, None
                if not path.is_file(): return 404, None
                if path.stat().st_size > limit: return 413, None
                referenced.add(relative); return 200, path
            if u.scheme not in ('http', 'https'): return 0, None
            try:
                with urllib.request.urlopen(url, timeout=15) as response:
                    path = Path(work) / str(len(list(Path(work).iterdir())))
                    total = 0
                    with path.open('wb') as out:
                        while chunk := response.read(256 * 1024):
                            total += len(chunk)
                            if total > limit: return 413, None
                            out.write(chunk)
                    return response.status, path
            except urllib.error.HTTPError as e: return e.code, None
            except (OSError, ValueError): return 0, None
        source_url = base + '/apps.json' if a.dir else a.url
        status, path = get(source_url, 2 * 1024 * 1024)
        check(status == 200, f'GET {source_url} -> {status}')
        try: src = json.loads(path.read_bytes()) if path else {}
        except (OSError, ValueError): src = {}; check(False, 'source is not valid JSON')
        if not isinstance(src, dict): check(False, 'source is not a JSON object'); src = {}
        for key in ('name', 'identifier', 'apps'): check(key in src, f"source has '{key}'")
        apps = src.get('apps')
        if not check(isinstance(apps, list) and bool(apps), 'source lists at least one app'): apps = []
        for app in apps:
            if not check(isinstance(app, dict), 'app is an object'): continue
            tag = str(app.get('bundleIdentifier', '?'))
            for key in ('name', 'bundleIdentifier', 'developerName', 'localizedDescription', 'iconURL', 'versions'):
                check(key in app, f"{tag}: has '{key}'")
            status, icon = get(app.get('iconURL'), 8 * 1024 * 1024)
            check(status == 200, f'{tag}: icon URL -> {status}')
            if icon:
                try: opaque_icon(icon)
                except ValueError as error: check(False, str(error))
            versions = app.get('versions')
            if not check(isinstance(versions, list) and bool(versions), tag + ': nonempty versions'): continue
            identities = set()
            for v in versions:
                if not check(isinstance(v, dict), tag + ': version is an object'): continue
                required = ('version', 'buildVersion', 'date', 'downloadURL', 'size', 'minOSVersion', 'sha256')
                if not check(all(k in v for k in required), tag + ': complete version metadata including SHA-256'): continue
                identity = (str(v['version']), str(v['buildVersion']))
                check(identity not in identities, tag + ': unique version/build'); identities.add(identity)
                if not check(type(v['size']) is int and 0 < v['size'] < 0xffffffff, tag + ': valid classic-ZIP artifact size'): continue
                status, artifact = get(v['downloadURL'], v['size'])
                check(status == 200, tag + f': download URL -> {status}')
                if not artifact: continue
                check(artifact.stat().st_size == v['size'], tag + ': IPA size matches')
                check(digest(artifact) == v['sha256'], tag + ': IPA SHA-256 matches')
                status, checksum = get(v['downloadURL'] + '.sha256', 4096)
                expected = str(v['sha256']) + '  ' + unquote(urlsplit(v['downloadURL']).path.rsplit('/', 1)[-1]) + '\n'
                check(status == 200 and checksum.read_text(encoding='utf-8') == expected, tag + ': checksum sidecar matches')
                try:
                    info = metadata(artifact)
                    for key, expected in [('CFBundleIdentifier', app.get('bundleIdentifier')), ('CFBundleShortVersionString', v['version']), ('CFBundleVersion', v['buildVersion']), ('MinimumOSVersion', v['minOSVersion'])]:
                        check(info.get(key, '17.0' if key == 'MinimumOSVersion' else None) == expected, tag + ': ' + key + ' matches')
                except Exception as error: check(False, tag + ': IPA unreadable: ' + str(error))
            first = versions[0]
            if isinstance(first, dict):
                for old, current in [('version', 'version'), ('downloadURL', 'downloadURL'), ('size', 'size'), ('versionDate', 'date')]:
                    check(app.get(old) == first.get(current), tag + ': legacy ' + old + ' matches newest version')
        if a.dir:
            required = {'apps.json', 'index.html', 'icon.png', 'LICENSE', 'NOTICE'}
            present = {str(p.relative_to(a.dir)) for p in Path(a.dir).rglob('*') if p.is_file() or p.is_symlink()}
            check(required <= present, 'all public stage files present')
            check(not (present - required - referenced), 'no unexpected files in the staged directory ' + str(sorted(present - required - referenced)))
            check(not any(p.is_symlink() for p in Path(a.dir).rglob('*')), 'stage contains no symlinks')
        print(f'RESULT: {len(failures)} failures')
    return bool(failures)

if __name__ == '__main__': raise SystemExit(main())
