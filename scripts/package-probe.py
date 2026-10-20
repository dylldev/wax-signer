#!/usr/bin/env python3
"""Package the source-built probe into Wax's resources; never upload or sign anything."""
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import stat
import tempfile
import zipfile
from pathlib import Path


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(256 * 1024), b''): h.update(chunk)
    return h.hexdigest()


def package(app, source, out):
    if app.is_symlink() or not app.is_dir(): raise ValueError('expected a built probe app directory')
    plist = app/'Info.plist'
    if plist.is_symlink() or plist.stat().st_size > 1024*1024: raise ValueError('unsafe/oversized probe plist')
    info = plistlib.loads(plist.read_bytes())
    if not isinstance(info,dict): raise ValueError('probe plist must be a dictionary')
    for key, expected in [('CFBundleIdentifier','io.github.dylldev.wax.probe'), ('CFBundleShortVersionString','1.0'), ('CFBundleVersion','1')]:
        if info.get(key) != expected: raise ValueError('unexpected probe ' + key)
    types = info.get('CFBundleURLTypes')
    if not isinstance(types,list) or any(not isinstance(t,dict) or not isinstance(t.get('CFBundleURLSchemes'),list) for t in types): raise ValueError('invalid probe URL types')
    schemes = [s for entry in types for s in entry['CFBundleURLSchemes']]
    if schemes != ['waxprobe']: raise ValueError('probe must register only waxprobe')
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable,str) or Path(executable).name != executable or not (app/executable).is_file(): raise ValueError('missing/unsafe probe executable')
    if not (app/executable).stat().st_mode & 0o111: raise ValueError('probe executable has no execute permission')
    if (app/executable).is_symlink(): raise ValueError('unsafe probe executable')
    with (app/executable).open('rb') as binary:
        if binary.read(4) not in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'): raise ValueError('probe executable is not a Mach-O shape')
    files = sorted(p for p in app.rglob('*') if not p.is_dir())
    if any(p.is_symlink() or not stat.S_ISREG(p.stat().st_mode) for p in files): raise ValueError('probe bundle must contain regular files only')
    if any(p.is_symlink() for p in app.rglob('*')): raise ValueError('probe bundle contains a symlink')
    if len(files) > 4096 or sum(p.stat().st_size for p in files) > 32 * 1024 * 1024: raise ValueError('unexpectedly large probe bundle')
    source_files = sorted(p for p in source.rglob('*') if p.is_file())
    if not source_files or any(p.is_symlink() or p.name not in ('WaxProbe.swift','Info.plist') or p.stat().st_size > 65536 for p in source_files): raise ValueError('missing/unsafe probe sources')
    public_source = {str(p.relative_to(source)): sha256(p) for p in source_files}
    out.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.wax-probe-',dir=out) as work:
        archive = Path(work)/'WaxProbe.ipa'
        with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for p in files:
                entry = zipfile.ZipInfo('Payload/WaxProbe.app/'+p.relative_to(app).as_posix(),date_time=(1980,1,1,0,0,0))
                entry.create_system=3;entry.external_attr=p.stat().st_mode << 16;entry.compress_type=zipfile.ZIP_DEFLATED
                entry.file_size=p.stat().st_size
                with p.open('rb') as src, z.open(entry,'w') as dst: shutil.copyfileobj(src,dst,256*1024)
        report = dict(schemaVersion=1,probeVersion=1,bundleIdentifier=info['CFBundleIdentifier'],version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],scheme='waxprobe',
            platforms=info.get('CFBundleSupportedPlatforms',[]),ipaSHA256=sha256(archive),executableSHA256=sha256(app/executable),sources=public_source)
        manifest=Path(work)/'probe-build.json';manifest.write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
        os.replace(archive,out/'WaxProbe.ipa');os.replace(manifest,out/'probe-build.json')
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app',type=Path,required=True);parser.add_argument('--source',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    a=parser.parse_args()
    try: package(a.app,a.source,a.out)
    except (OSError,ValueError,KeyError,TypeError) as e: parser.error(str(e))

if __name__=='__main__': main()
