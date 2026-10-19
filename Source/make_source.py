#!/usr/bin/env python3
"""Builds an AltStore/SideStore-compatible source for Wax.

  python3 Source/make_source.py --ipa Wax-0.3.1.ipa --base-url https://example.com/wax --out dist

Writes dist/apps.json and copies the IPA into dist/. Upload the whole dist/ folder to any static host
(GitHub Pages, Cloudflare Pages, a release asset behind a stable URL...). Users add
<base-url>/apps.json as a source. Add icon.png (1024x1024) to dist/ for the icon.

Nothing is uploaded by this script.
"""
import argparse, json, os, shutil, datetime, tempfile, zipfile
from pathlib import Path
from source_artifact import base_url, metadata, opaque_icon, version_record
from html import escape
from urllib.parse import quote

ap = argparse.ArgumentParser()
ap.add_argument("--ipa", required=True)
ap.add_argument("--base-url", required=True, help="public URL the dist/ folder will be served from, no trailing slash")
ap.add_argument("--out", default="dist")
ap.add_argument("--capabilities", required=True, choices=["inspector", "signer-export", "signer-install"], help="capabilities of this exact tested binary, not the current source")
ap.add_argument("--date", help="ISO release date; set for reproducible generation")
ap.add_argument("--icon", required=True, help="1024x1024 PNG copied to <out>/icon.png")
ap.add_argument("--extra", action="append", default=[], help="additional file copied as-is (e.g. LICENSE, NOTICE)")
ap.add_argument("--keep-versions", default=None, help="existing apps.json to carry older versions over from")
a = ap.parse_args()

try:
    base = base_url(a.base_url)
    date = a.date or datetime.date.today().isoformat()
    datetime.date.fromisoformat(date)
    opaque_icon(a.icon)
    info, new_version = version_record(a.ipa, base, date)
    if os.path.exists(a.out) and (not os.path.isdir(a.out) or os.listdir(a.out)):
        raise ValueError('output must be absent or empty; existing stage was not changed')
    extras = {}
    for path in a.extra:
        name = os.path.basename(path)
        if name not in ('LICENSE', 'NOTICE') or name in extras: raise ValueError('extras must be unique public LICENSE/NOTICE files')
        extras[name] = path
    bundle_id, version, build = info['CFBundleIdentifier'], info['CFBundleShortVersionString'], info['CFBundleVersion']
    name = info.get('CFBundleDisplayName') or info.get('CFBundleName') or 'Wax'
    ipa_file = os.path.basename(a.ipa)
    if any(ord(c) < 32 for c in ipa_file) or not ipa_file.lower().endswith('.ipa'): raise ValueError('IPA filename must end in .ipa')
    copies = {ipa_file: a.ipa}
    versions = [new_version]
    if a.keep_versions:
        with open(a.keep_versions) as f: old = json.load(f)
        for app in old['apps']:
            if app['bundleIdentifier'] != bundle_id: continue
            for v in app['versions']:
                from urllib.parse import unquote, urlsplit
                filename = unquote(urlsplit(v['downloadURL']).path.rsplit('/', 1)[-1])
                if os.path.basename(filename) != filename or not filename.endswith('.ipa'): raise ValueError('unsafe historical IPA filename')
                file = os.path.join(os.path.dirname(a.keep_versions), filename)
                old_info, entry = version_record(file, base, v['date'])
                for key in ('version', 'buildVersion', 'size', 'minOSVersion'):
                    if entry[key] != v[key]: raise ValueError('historical artifact metadata mismatch: ' + key)
                if old_info['CFBundleIdentifier'] != bundle_id: raise ValueError('historical bundle identifier mismatch')
                if v.get('sha256', entry['sha256']) != entry['sha256']: raise ValueError('historical SHA-256 mismatch')
                if (entry['version'], entry['buildVersion']) == (version, build):
                    if entry['sha256'] != new_version['sha256']: raise ValueError('same version/build identifies different IPA bytes')
                    continue
                if filename in copies: raise ValueError('historical artifact filename collision')
                copies[filename] = file; versions.append(entry)
except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as error:
    ap.error(str(error))

capability = {
    'inspector': 'Legacy inspector build: inspect IPA metadata and manage certificates/profiles. This historical build does not sign or install apps.',
    'signer-export': 'Sign and inspect IPAs on-device using your own valid certificates and provisioning profiles. Export signed IPAs; installation remains subject to iOS provisioning and trust decisions.',
    'signer-install': 'Sign and inspect IPAs on-device using your own valid certificates and provisioning profiles. Export or hand off installation through supported configured hosts; iOS decides provisioning and trust acceptance.',
}[a.capabilities]

source = {
    "name": "Wax",
    "identifier": "dev.localsigner.source",
    "subtitle": "Free on-device IPA tools",
    "description": capability,
    "iconURL": f"{base}/icon.png",
    "tintColor": "8E2A24",
    "apps": [{
        "name": name,
        "bundleIdentifier": bundle_id,
        "developerName": "Wax",
        "subtitle": "On-device IPA tools",
        "localizedDescription": capability,
        "iconURL": f"{base}/icon.png",
        "tintColor": "8E2A24",
        "screenshotURLs": [],
        "versions": versions,
        # legacy single-version fields, for older source readers
        "version": version,
        "versionDate": new_version["date"],
        "downloadURL": new_version["downloadURL"],
        "size": new_version["size"],
    }],
    "news": [],
}

html_base = escape(base, quote=True)
html_source_link = escape(quote(base + "/apps.json", safe=""), quote=True)
html_ipa = escape(quote(ipa_file), quote=True)
html_version = escape(version)
html_build = escape(build)

# Static landing page: one-tap links for the common sideloaders. No scripts, no analytics.
page = f"""<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Wax</title>
<style>body{{font:17px/1.5 -apple-system,system-ui,sans-serif;max-width:32rem;margin:3rem auto;padding:0 1rem;color:#1b1613;background:#ede6d8}}
img{{width:96px;height:96px;border-radius:22%}}a{{color:#8e2a24}}code{{word-break:break-all}}</style>
<img src="icon.png" alt="">
<h1>Wax</h1>
<p>{escape(capability)}</p>
<p><a href="altstore://source?url={html_source_link}">Add to AltStore</a> &middot;
<a href="sidestore://source?url={html_source_link}">Add to SideStore</a></p>
<p>Source URL: <code>{html_base}/apps.json</code></p>
<p><a href="{html_ipa}">Download the .ipa</a> ({html_version}, build {html_build}). Your sideloader must sign this distribution IPA with valid provisioning.</p>
"""
# Prepare everything away from the destination. Failure cannot leave a plausible partial source.
out = Path(a.out).absolute()
out.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='.wax-source-', dir=out.parent) as work:
    stage = Path(work) / 'stage'; stage.mkdir()
    for filename, file in copies.items(): shutil.copyfile(file, stage / filename)
    # Re-read copied bytes: a changing input cannot publish a feed for a different artifact.
    for entry in versions:
        from source_artifact import digest
        from urllib.parse import unquote, urlsplit
        filename = unquote(urlsplit(entry['downloadURL']).path.rsplit('/', 1)[-1])
        if digest(stage / filename) != entry['sha256']: raise ValueError('IPA changed during staging')
        (stage / (filename + '.sha256')).write_text(entry['sha256'] + '  ' + filename + '\n', encoding='utf-8')
    shutil.copyfile(a.icon, stage / 'icon.png')
    for filename, file in extras.items(): shutil.copyfile(file, stage / filename)
    (stage / 'index.html').write_text(page, encoding='utf-8')
    (stage / 'apps.json').write_text(json.dumps(source, indent=2) + '\n', encoding='utf-8')
    if out.exists(): out.rmdir()  # allowed only if empty; never remove an existing file
    os.replace(stage, out)
print(f"wrote {a.out}/apps.json  ({bundle_id} {version} build {build}, {new_version['size']} bytes)")
print(f"source URL once hosted: {base}/apps.json")
