import hashlib
import io
import json
import plistlib
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from prepare_release import prepare
from test_release_integrity import icon

class ReleaseCandidateGate(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.repo=self.root/'repo';self.repo.mkdir();self.out=self.root/'candidate'
        self.git('init','-q');self.git('config','user.name','Fixture');self.git('config','user.email','fixture@example.invalid')
        (self.repo/'Prototype/WaxProbe').mkdir(parents=True)
        (self.repo/'Prototype/WaxProbe/WaxProbe.swift').write_text('public fixture source')
        (self.repo/'Prototype/WaxProbe/Info.plist').write_bytes(plistlib.dumps({'Fixture':True}))
        for name in ('LICENSE','NOTICE'): (self.repo/name).write_text(name)
        (self.repo/'.gitignore').write_text('private.p12\n')
        self.git('add','.');self.git('commit','-qm','fixture');self.git('tag','-a','v1.0','-m','fixture release')
        self.icon=self.root/'icon.png';icon(self.icon)
    def git(self,*args):return subprocess.check_output(['git','-C',str(self.repo),*args],stderr=subprocess.DEVNULL).decode().strip()
    def build(self,source,out,flavor,feed,domain):
        self.assertFalse((source/'private.p12').exists());self.assertFalse((source/'untracked-token.txt').exists())
        # Synthetic transport fixture: does not establish Swift compilation or a cryptographic signature.
        probe_bytes=io.BytesIO();binary=b'\xcf\xfa\xed\xfe'+b'fixture executable (not compiled)'
        with zipfile.ZipFile(probe_bytes,'w') as z:
            z.writestr('Payload/WaxProbe.app/Info.plist',plistlib.dumps(dict(CFBundleIdentifier='io.github.dylldev.wax.probe',CFBundleShortVersionString='1.0',CFBundleVersion='1',CFBundleExecutable='WaxProbe')))
            z.writestr('Payload/WaxProbe.app/WaxProbe',binary)
        probe=probe_bytes.getvalue()
        manifest=dict(schemaVersion=1,probeVersion=1,bundleIdentifier='io.github.dylldev.wax.probe',version='1.0',build='1',scheme='waxprobe',ipaSHA256=hashlib.sha256(probe).hexdigest(),executableSHA256=hashlib.sha256(binary).hexdigest(),sources={n:hashlib.sha256((source/'Prototype/WaxProbe'/n).read_bytes()).hexdigest() for n in ('WaxProbe.swift','Info.plist')})
        with zipfile.ZipFile(out/'Wax-1.0.ipa','w') as z:
            z.writestr('Payload/Wax.app/Info.plist',plistlib.dumps(dict(CFBundleIdentifier='io.github.dylldev.wax',CFBundleShortVersionString='1.0',CFBundleVersion='7',WAX_DEFAULT_FEED=feed,WAX_INSTALL_DOMAIN=domain)))
            z.writestr('Payload/Wax.app/probe-build.json',json.dumps(manifest));z.writestr('Payload/Wax.app/WaxProbe.ipa',probe)
        return dict(xcode='fixture Xcode (not executed)',swift='fixture Swift (not executed)')
    def prepare(self,**changes):
        args=dict(repo=self.repo,tag='v1.0',output=self.out,icon=self.icon,base='https://dylldev.github.io/wax',date='2026-10-19',expected_build='7',flavor='no-feed',builder=self.build)
        args.update(changes);return prepare(**args)
    def test_actual_stage_bytes_match_provenance_and_exclude_local_files(self):
        (self.repo/'private.p12').write_text('must never enter source export');(self.repo/'untracked-token.txt').write_text('must never enter source export')
        report=self.prepare();artifact=self.out/'stage/Wax-1.0.ipa'
        self.assertEqual(report['source']['commit'],self.git('rev-parse','HEAD'))
        self.assertEqual(report['artifact']['sha256'],hashlib.sha256(artifact.read_bytes()).hexdigest())
        self.assertEqual(report['verification']['physicalInstall'],'NOT_RECORDED')
        self.assertEqual(set(p.name for p in self.out.iterdir()),{'stage','provenance.json'})
    def test_wrong_build_or_bundle_version_never_creates_candidate(self):
        with self.assertRaises(ValueError):self.prepare(expected_build='8')
        self.assertFalse(self.out.exists())
    def test_lightweight_or_nonmatching_head_tag_is_refused_before_build(self):
        self.git('tag','v2.0')
        with self.assertRaises(ValueError):self.prepare(tag='v2.0')
        (self.repo/'later').write_text('later');self.git('add','.');self.git('commit','-qm','later')
        with self.assertRaises(ValueError):self.prepare()
        self.assertFalse(self.out.exists())
    def test_missing_probe_evidence_is_not_release_ready(self):
        def missing(source,out,*args):
            result=self.build(source,out,*args)
            with zipfile.ZipFile(out/'Wax-1.0.ipa','a') as z:z.writestr('Payload/Wax.app/probe-build.json', '{}')
            return result
        with self.assertRaises(ValueError):self.prepare(builder=missing)
        self.assertFalse(self.out.exists())
    def test_builder_failure_preserves_previous_output(self):
        self.out.mkdir();(self.out/'valuable').write_text('keep')
        with self.assertRaises(ValueError):self.prepare(builder=lambda *_:self.fail('existing output must stop before building'))
        self.assertEqual((self.out/'valuable').read_text(),'keep')
    def test_build_failure_cleans_owned_scratch_without_publishing(self):
        def failed(*args):raise OSError('injected build failure')
        with self.assertRaises(OSError):self.prepare(builder=failed)
        self.assertFalse(self.out.exists());self.assertFalse(list(self.root.glob('.wax-candidate-*')))
    def test_public_configuration_requires_exact_embedded_flavor(self):
        for feed,domain in [('https://user:secret@example.invalid/feed','name.example'),('https://example.invalid/feed','name..example')]:
            with self.assertRaises(ValueError):self.prepare(flavor='configured-feed',feed=feed,domain=domain)
        report=self.prepare(flavor='configured-feed',feed='https://public.example/feed.json',domain='loop.example')
        self.assertEqual(report['configuration']['flavor'],'configured-feed')
        self.assertNotIn('hand off installation', (self.out/'stage/apps.json').read_text(), 'configuration alone cannot claim tested install routes')
    def test_tag_movement_during_build_cannot_silently_change_source_binding(self):
        def moved(*args):
            result=self.build(*args);self.git('tag','-f','-a','v1.0','-m','moved annotation');return result
        with self.assertRaises(ValueError):self.prepare(builder=moved)
        self.assertFalse(self.out.exists())
    def test_extra_build_artifact_and_source_manifest_mismatch_are_rejected(self):
        def extra(source,out,*args):
            result=self.build(source,out,*args);(out/'another.ipa').write_bytes(b'not intended');return result
        with self.assertRaises(ValueError):self.prepare(builder=extra)
        def mismatched(source,out,*args):
            result=self.build(source,out,*args);(source/'Prototype/WaxProbe/WaxProbe.swift').write_text('changed');return result
        with self.assertRaises(ValueError):self.prepare(builder=mismatched)
        self.assertFalse(self.out.exists())
