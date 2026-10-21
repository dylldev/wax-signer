#!/usr/bin/env python3
"""Validates a Wax source by fetching it the way a client would.

  python3 Source/validate_source.py http://127.0.0.1:8765/wax/apps.json
  python3 Source/validate_source.py --dir dist --expect-base https://user.github.io/wax

--dir mode checks a staged directory offline: every URL must start with --expect-base and map to a file in
the directory, and no file may exist that apps.json does not need (other than the allowed public files).

Checks: JSON shape, every URL answers 200, IPA size and zip integrity match the declared values, the IPA's
bundle id and version match the entry, the icon is a 1024x1024 opaque PNG. Exits non-zero on any failure.
"""
import io, json, plistlib, struct, sys, urllib.error, urllib.request, zipfile

import os
from urllib.parse import unquote, urlsplit
fails = []
LOCAL = None
if sys.argv[1] == "--dir":
    LOCAL = sys.argv[2]
    BASE = sys.argv[sys.argv.index("--expect-base") + 1].rstrip("/")
    url = BASE + "/apps.json"
else:
    url = sys.argv[1]
def check(ok, msg):
    print(("ok    " if ok else "FAIL  ") + msg)
    if not ok: fails.append(msg)

def get(u):
    if LOCAL is not None:
        base_parts, parts = urlsplit(BASE), urlsplit(u)
        prefix = base_parts.path.rstrip("/") + "/"
        if (parts.scheme, parts.netloc) != (base_parts.scheme, base_parts.netloc) or not parts.path.startswith(prefix):
            return 0, b""
        path = os.path.realpath(os.path.join(LOCAL, unquote(parts.path[len(prefix):])))
        if os.path.commonpath((os.path.realpath(LOCAL), path)) != os.path.realpath(LOCAL):
            return 0, b""
        try:
            with open(path, "rb") as f:
                return 200, f.read()
        except OSError:
            return 404, b""
    if urlsplit(u).scheme not in ("http", "https"):
        return 0, b""
    try:
        with urllib.request.urlopen(u, timeout=15) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return 0, b""

st, body = get(url)
check(st == 200, f"GET {url} -> {st}")
try:
    src = json.loads(body)
except json.JSONDecodeError:
    check(False, "source is not valid JSON")
    src = {}
if not isinstance(src, dict):
    check(False, "source is not a JSON object")
    src = {}
for k in ("name", "identifier", "apps"):
    check(k in src, f"source has '{k}'")
check(isinstance(src.get("apps"), list) and src["apps"], "source lists at least one app")

for app in src.get("apps", []):
    n = app.get("bundleIdentifier", "?")
    for k in ("name", "bundleIdentifier", "developerName", "localizedDescription", "iconURL", "versions"):
        check(k in app, f"{n}: has '{k}'")
    st, icon = get(app["iconURL"])
    check(st == 200, f"{n}: icon URL -> {st}")
    check(icon[:8] == b"\x89PNG\r\n\x1a\n", f"{n}: icon is a PNG")
    if len(icon) >= 26:
        w, h, depth, ctype = struct.unpack(">IIBB", icon[16:26])
        check((w, h) == (1024, 1024), f"{n}: icon is {w}x{h}")
        check(ctype in (0, 2), f"{n}: icon has no alpha channel (colour type {ctype})")

    for v in app.get("versions", []):
        tag = f"{n} {v.get('version')} ({v.get('buildVersion')})"
        for k in ("version", "buildVersion", "date", "downloadURL", "size", "minOSVersion"):
            check(k in v, f"{tag}: has '{k}'")
        st, data = get(v["downloadURL"])
        check(st == 200, f"{tag}: download URL -> {st}")
        check(len(data) == v["size"], f"{tag}: size {len(data)} == declared {v['size']}")
        try:
            z = zipfile.ZipFile(io.BytesIO(data))
            check(z.testzip() is None, f"{tag}: zip integrity")
            info = plistlib.loads(z.read(next(x for x in z.namelist() if x.count("/") == 2 and x.endswith(".app/Info.plist"))))
            check(info["CFBundleIdentifier"] == n, f"{tag}: IPA bundle id {info['CFBundleIdentifier']}")
            check(info["CFBundleShortVersionString"] == v["version"], f"{tag}: IPA version {info['CFBundleShortVersionString']}")
            check(info["CFBundleVersion"] == v["buildVersion"], f"{tag}: IPA build {info['CFBundleVersion']}")
            check(info.get("MinimumOSVersion") == v["minOSVersion"], f"{tag}: min OS {info.get('MinimumOSVersion')}")
        except Exception as e:
            check(False, f"{tag}: IPA unreadable: {e}")

if LOCAL is not None:
    allowed = {"apps.json", "index.html", "icon.png", "LICENSE", "NOTICE"}
    referenced = set()
    for app in src.get("apps", []):
        referenced.add(app["iconURL"][len(BASE) + 1:])
        for v in app.get("versions", []):
            referenced.add(v["downloadURL"][len(BASE) + 1:])
    present = set()
    for root, _, files in os.walk(LOCAL):
        for f in files:
            present.add(os.path.relpath(os.path.join(root, f), LOCAL))
    extra = present - allowed - referenced
    check(not extra, f"no unexpected files in the staged directory {sorted(extra) if extra else ''}")
    check(allowed <= present, f"all of {sorted(allowed)} present")

print("\nRESULT:", "FAILED" if fails else "all checks passed", f"({len(fails)} failures)")
sys.exit(1 if fails else 0)
