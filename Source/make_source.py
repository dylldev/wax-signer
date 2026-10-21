#!/usr/bin/env python3
"""Builds an AltStore/SideStore-compatible source for Wax.

  python3 Source/make_source.py --ipa Wax-0.3.1.ipa --base-url https://example.com/wax --out dist

Writes dist/apps.json and copies the IPA into dist/. Upload the whole dist/ folder to any static host
(GitHub Pages, Cloudflare Pages, a release asset behind a stable URL...). Users add
<base-url>/apps.json as a source. Add icon.png (1024x1024) to dist/ for the icon.

Nothing is uploaded by this script.
"""
import argparse, json, os, plistlib, shutil, zipfile, datetime
from html import escape
from urllib.parse import quote

ap = argparse.ArgumentParser()
ap.add_argument("--ipa", required=True)
ap.add_argument("--base-url", required=True, help="public URL the dist/ folder will be served from, no trailing slash")
ap.add_argument("--out", default="dist")
ap.add_argument("--icon", help="1024x1024 PNG copied to <out>/icon.png")
ap.add_argument("--extra", action="append", default=[], help="additional file copied as-is (e.g. LICENSE, NOTICE)")
ap.add_argument("--keep-versions", default=None, help="existing apps.json to carry older versions over from")
a = ap.parse_args()

with zipfile.ZipFile(a.ipa) as z:
    info_name = next(n for n in z.namelist() if n.count("/") == 2 and n.endswith(".app/Info.plist"))
    info = plistlib.loads(z.read(info_name))

bundle_id = info["CFBundleIdentifier"]
version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
min_os = info.get("MinimumOSVersion", "17.0")
name = info.get("CFBundleDisplayName") or info.get("CFBundleName") or "Wax"
base = a.base_url.rstrip("/")
ipa_file = os.path.basename(a.ipa)

new_version = {
    "version": version,
    "buildVersion": build,
    "date": datetime.date.today().isoformat(),
    "downloadURL": f"{base}/{ipa_file}",
    "size": os.path.getsize(a.ipa),
    "minOSVersion": min_os,
    "localizedDescription": f"Wax {version} ({build})",
}

versions = [new_version]
if a.keep_versions and os.path.exists(a.keep_versions):
    old = json.load(open(a.keep_versions))
    for app in old.get("apps", []):
        if app.get("bundleIdentifier") == bundle_id:
            versions += [v for v in app.get("versions", []) if v.get("buildVersion") != build]

source = {
    "name": "Wax",
    "identifier": "dev.localsigner.source",
    "subtitle": "Local IPA inspector and signer",
    "description": "Wax checks IPA files and manages your own signing certificates and provisioning profiles on-device.",
    "iconURL": f"{base}/icon.png",
    "tintColor": "8E2A24",
    "apps": [{
        "name": name,
        "bundleIdentifier": bundle_id,
        "developerName": "Wax",
        "subtitle": "Inspect IPAs, manage certificates and profiles",
        "localizedDescription": (
            "Import an .ipa and see its real metadata: bundle id, version, minimum iOS, executable and whether "
            "signature or profile files are present. Import your own .p12 and provisioning profiles; private keys "
            "stay in the iOS Keychain and passwords are never stored.\n\n"
            "This build does not sign or install apps yet. Signature validity and installation eligibility are "
            "never claimed."),
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

os.makedirs(a.out, exist_ok=True)
shutil.copy2(a.ipa, os.path.join(a.out, ipa_file))
if a.icon:
    shutil.copy2(a.icon, os.path.join(a.out, "icon.png"))
for extra in a.extra:
    shutil.copy2(extra, os.path.join(a.out, os.path.basename(extra)))

html_base = escape(base, quote=True)
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
<p>Inspect IPA files and manage your own signing certificates and profiles on-device.</p>
<p><a href="altstore://source?url={html_base}/apps.json">Add to AltStore</a> &middot;
<a href="sidestore://source?url={html_base}/apps.json">Add to SideStore</a></p>
<p>Source URL: <code>{html_base}/apps.json</code></p>
<p><a href="{html_ipa}">Download the .ipa</a> ({html_version}, build {html_build}). Unsigned: your sideloader signs it.</p>
"""
open(os.path.join(a.out, "index.html"), "w").write(page)
with open(os.path.join(a.out, "apps.json"), "w") as f:
    json.dump(source, f, indent=2)
print(f"wrote {a.out}/apps.json  ({bundle_id} {version} build {build}, {new_version['size']} bytes)")
print(f"source URL once hosted: {base}/apps.json")
