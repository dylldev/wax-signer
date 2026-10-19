#!/usr/bin/env python3
"""Build a reviewable release candidate from an annotated source tag. Never publish or deploy."""
import argparse
import hashlib
import io
import plistlib
import stat
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from source_artifact import base_url, digest, metadata


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL).decode().strip()


def tagged_source(repo, tag):
    if not re.fullmatch(r'v\d+(?:\.\d+){1,3}', tag): raise ValueError('expected an explicit vVERSION release tag')
    ref = 'refs/tags/' + tag
    if git(repo, 'cat-file', '-t', ref) != 'tag': raise ValueError('release tag must be annotated')
    commit = git(repo, 'rev-parse', '--verify', ref + '^{commit}')
    if commit != git(repo, 'rev-parse', '--verify', 'HEAD'): raise ValueError('HEAD must match the selected release tag')
    return dict(commit=commit, tag=tag, tagObject=git(repo, 'rev-parse', '--verify', ref))


def read_member(archive, name, limit):
    item = archive.getinfo(name)
    if item.file_size > limit: raise ValueError('oversized release metadata')
    return archive.read(item)


def probe_evidence(ipa, source):
    """Check actual nested bytes and bind the source-built probe manifest to exported public sources."""
    with zipfile.ZipFile(ipa) as z:
        if len(z.namelist()) != len(set(z.namelist())): raise ValueError('duplicate release archive paths')
        app = [n.rsplit('/', 1)[0] for n in z.namelist() if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
        if len(app) != 1: raise ValueError('ambiguous release app')
        manifest = json.loads(read_member(z, app[0]+'/probe-build.json', 65536))
        probe = read_member(z, app[0]+'/WaxProbe.ipa', 32*1024*1024)
    if (manifest.get('schemaVersion'), manifest.get('probeVersion'), manifest.get('bundleIdentifier'), manifest.get('version'), manifest.get('build'), manifest.get('scheme')) != (1,1,'io.github.dylldev.wax.probe','1.0','1','waxprobe'):
        raise ValueError('missing or unsupported source-built probe evidence')
    if manifest.get('platforms')!=['iPhoneOS']: raise ValueError('release probe was not built for physical iOS')
    if manifest.get('ipaSHA256') != hashlib.sha256(probe).hexdigest(): raise ValueError('probe bytes disagree with build evidence')
    with zipfile.ZipFile(io.BytesIO(probe)) as nested:
        entries=nested.infolist(); names=[entry.filename for entry in entries]
        if len(entries)>4096 or len(names)!=len(set(names)) or sum(entry.file_size for entry in entries)>32*1024*1024: raise ValueError('invalid probe archive geometry')
        for entry in entries:
            path=PurePosixPath(entry.filename)
            if str(path)!=entry.filename.rstrip('/') or '..' in path.parts or not entry.filename.startswith('Payload/WaxProbe.app/') or stat.S_ISLNK(entry.external_attr>>16): raise ValueError('unsafe probe entry')
        info=plistlib.loads(read_member(nested,'Payload/WaxProbe.app/Info.plist',1024*1024))
        if any(info.get(k)!=v for k,v in [('CFBundleIdentifier','io.github.dylldev.wax.probe'),('CFBundleShortVersionString','1.0'),('CFBundleVersion','1')]): raise ValueError('wrong nested probe metadata')
        if info.get('CFBundleSupportedPlatforms')!=['iPhoneOS']: raise ValueError('nested probe is not a physical iOS build')
        executable=info.get('CFBundleExecutable')
        if not isinstance(executable,str) or PurePosixPath(executable).name!=executable or executable in ('.','..'): raise ValueError('unsafe probe executable')
        binary=read_member(nested,'Payload/WaxProbe.app/'+executable,32*1024*1024)
        if binary[:4] not in (b'\xcf\xfa\xed\xfe',b'\xca\xfe\xba\xbe') or manifest.get('executableSHA256')!=hashlib.sha256(binary).hexdigest(): raise ValueError('probe executable disagrees with evidence')
        if nested.testzip() is not None: raise ValueError('corrupted nested probe')
    sources = manifest.get('sources')
    if not isinstance(sources, dict) or set(sources) != {'WaxProbe.swift','Info.plist'}: raise ValueError('missing public probe sources')
    for name, value in sources.items():
        if digest(source/'Prototype/WaxProbe'/name) != value: raise ValueError('probe source hash differs from tagged source')
    return manifest


def public_configuration(info, flavor):
    feed, domain = info.get('WAX_DEFAULT_FEED', ''), info.get('WAX_INSTALL_DOMAIN', '')
    if not isinstance(feed, str) or not isinstance(domain, str): raise ValueError('invalid public configuration')
    if flavor == 'no-feed':
        if feed or domain: raise ValueError('no-feed candidate contains unexpected install configuration')
    elif flavor == 'configured-feed':
        base_url(feed) # refuse credentials/query/fragment; do not print rejected values
        if len(domain)>253 or '.' not in domain or not all(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label) for label in domain.split('.')):
            raise ValueError('configured-feed candidate requires a public DNS name')
    else: raise ValueError('unknown configuration flavor')
    return dict(flavor=flavor, feed=feed, domain=domain)


def live_build(source, output, flavor, feed, domain):
    # Fresh exported sources exclude local ignored configuration and private/untracked files.
    env = {k: v for k, v in os.environ.items() if k in ('PATH','HOME','TMPDIR','LANG','LC_ALL','DEVELOPER_DIR')}
    env['WAX_DEFAULT_FEED'] = feed; env['WAX_INSTALL_DOMAIN'] = domain
    subprocess.run(['bash', str(source/'scripts/build-release-ipa.sh'), str(output)], env=env, check=True)
    return dict(xcode=subprocess.check_output(['xcodebuild','-version'], env=env).decode().strip(),
                swift=subprocess.check_output(['xcrun','swift','--version'], env=env).decode().strip(),
                sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-version'], env=env).decode().strip(),
                xcodegen=subprocess.check_output(['xcodegen','--version'], env=env).decode().strip())


def prepare(repo, tag, output, icon, base, date, expected_build, flavor, feed='', domain='', builder=live_build, history=None):
    repo=Path(repo).resolve(); output=Path(output).absolute(); icon=Path(icon).resolve(); base=base_url(base)
    origin=tagged_source(repo,tag)
    if os.path.lexists(output): raise ValueError('candidate output already exists; refusing replacement')
    # Validate public arguments before a build. Reject unknown/local credential-bearing URLs.
    config=public_configuration(dict(WAX_DEFAULT_FEED=feed,WAX_INSTALL_DOMAIN=domain),flavor)
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.wax-candidate-',dir=output.parent) as temp:
        work=Path(temp); source=work/'source'; source.mkdir(); archive=work/'source.tar'
        with archive.open('wb') as stream:
            subprocess.run(['git','-C',str(repo),'archive','--format=tar',origin['commit']],stdout=stream,check=True)
        source_hash=digest(archive)
        with tarfile.open(archive) as tar: tar.extractall(source,filter='data')
        built=work/'built';built.mkdir()
        toolchain=builder(source,built,flavor,feed,domain)
        if not isinstance(toolchain,dict) or set(toolchain) != {'xcode','swift','sdk','xcodegen'} or any(not isinstance(v,str) or not v.strip() for v in toolchain.values()): raise ValueError('missing build toolchain evidence')
        ipas=list(built.glob('*.ipa'))
        if len(ipas)!=1 or ipas[0].is_symlink(): raise ValueError('build must produce exactly one regular IPA')
        ipa=ipas[0];info=metadata(ipa)
        if info.get('CFBundleSupportedPlatforms')!=['iPhoneOS']: raise ValueError('candidate is not a physical iOS build')
        if info['CFBundleIdentifier']!='io.github.dylldev.wax' or tag!='v'+info['CFBundleShortVersionString'] or info['CFBundleVersion']!=expected_build:
            raise ValueError('tag/build/bundle metadata disagrees with the built IPA')
        if public_configuration(info,flavor)!=config: raise ValueError('requested public configuration did not reach the artifact')
        probe=probe_evidence(ipa,source)
        candidate=work/'candidate'; candidate.mkdir(); stage=candidate/'stage'
        generate=[sys.executable,str(Path(__file__).with_name('make_source.py')),'--ipa',str(ipa),'--icon',str(icon),
            '--capabilities','signer-export','--date',date,'--base-url',base,'--out',str(stage),
            '--extra',str(source/'LICENSE'),'--extra',str(source/'NOTICE')]
        if history is not None: generate += ['--keep-versions',str(history)]
        subprocess.run(generate,check=True,stdout=subprocess.DEVNULL)
        subprocess.run([sys.executable,str(Path(__file__).with_name('validate_source.py')),'--dir',str(stage),'--expect-base',base],check=True,stdout=subprocess.DEVNULL)
        # Hash the staged copy, not just the pre-stage input. Stage validator independently checked its bytes.
        staged=stage/ipa.name
        report=dict(schemaVersion=1,source=origin,sourceArchiveSHA256=source_hash,toolchain=toolchain,configuration=config,
                    artifact=dict(filename=ipa.name,sha256=digest(staged),size=staged.stat().st_size,bundleIdentifier=info['CFBundleIdentifier'],
                                  version=info['CFBundleShortVersionString'],build=info['CFBundleVersion']),probe=probe,
                    toolingSHA256=digest(Path(__file__)),baseURL=base,releaseDate=date,
                    verification=dict(appleConformance='NOT_RECORDED',physicalInstall='NOT_RECORDED',physicalLaunch='NOT_RECORDED',bitReproducibility='NOT_ESTABLISHED'))
        (candidate/'provenance.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
        # Recheck mutable local refs after build; a moved tag cannot silently change the selected source.
        if tagged_source(repo,tag)!=origin: raise ValueError('source tag changed while building')
        if os.path.lexists(output): raise ValueError('candidate destination appeared during build; refusing replacement')
        os.rename(candidate,output)
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--tag',required=True)
    p.add_argument('--out',type=Path,required=True);p.add_argument('--icon',type=Path,required=True);p.add_argument('--base-url',required=True)
    p.add_argument('--date',required=True);p.add_argument('--build',required=True);p.add_argument('--flavor',choices=['no-feed','configured-feed'],required=True)
    p.add_argument('--feed',default='');p.add_argument('--domain',default='')
    retained=p.add_mutually_exclusive_group(required=True);retained.add_argument('--history',type=Path);retained.add_argument('--no-history',action='store_true')
    a=p.parse_args()
    try: prepare(a.repo,a.tag,a.out,a.icon,a.base_url,a.date,a.build,a.flavor,a.feed,a.domain,history=a.history)
    except (ValueError,OSError,KeyError,subprocess.CalledProcessError,zipfile.BadZipFile,tarfile.TarError): p.error('candidate preparation failed; check the tag, build evidence, public configuration and available tools; existing outputs preserved')
    print('Candidate prepared for review. No release or deployment performed.')
if __name__=='__main__':main()
