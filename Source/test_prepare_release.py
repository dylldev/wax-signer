import hashlib
import io
import json
import plistlib
import subprocess
import tempfile
import unittest
import zipfile
import warnings
from pathlib import Path
from prepare_release import prepare, live_build, main
from unittest.mock import patch
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
    def build(self,source,out,flavor,feed,domain,channel='standard'):
        self.assertFalse((source/'private.p12').exists());self.assertFalse((source/'untracked-token.txt').exists())
        # Synthetic transport fixture: does not establish Swift compilation or a cryptographic signature.
        probe_bytes=io.BytesIO();binary=b'\xcf\xfa\xed\xfe'+b'fixture executable (not compiled)'
        with zipfile.ZipFile(probe_bytes,'w') as z:
            z.writestr('Payload/WaxProbe.app/Info.plist',plistlib.dumps(dict(CFBundleIdentifier='io.github.dylldev.wax.probe',CFBundleShortVersionString='1.0',CFBundleVersion='1',CFBundleExecutable='WaxProbe',CFBundleSupportedPlatforms=['iPhoneOS'])))
            z.writestr('Payload/WaxProbe.app/WaxProbe',binary)
        probe=probe_bytes.getvalue()
        manifest=dict(schemaVersion=1,probeVersion=1,bundleIdentifier='io.github.dylldev.wax.probe',version='1.0',build='1',scheme='waxprobe',platforms=['iPhoneOS'],ipaSHA256=hashlib.sha256(probe).hexdigest(),executableSHA256=hashlib.sha256(binary).hexdigest(),sources={n:hashlib.sha256((source/'Prototype/WaxProbe'/n).read_bytes()).hexdigest() for n in ('WaxProbe.swift','Info.plist')})
        filename=('Wax-Dev' if channel=='dev' else 'Wax')+'-1.0.ipa'
        with zipfile.ZipFile(out/filename,'w') as z:
            z.writestr('Payload/Wax.app/Info.plist',plistlib.dumps(dict(CFBundleIdentifier='io.github.dylldev.wax.dev' if channel=='dev' else 'io.github.dylldev.wax',CFBundleDisplayName='Wax Dev' if channel=='dev' else 'Wax',CFBundleShortVersionString='1.0',CFBundleVersion='7',CFBundleSupportedPlatforms=['iPhoneOS'],WAX_DEFAULT_FEED=feed,WAX_INSTALL_DOMAIN=domain)))
            if channel=='dev':
                z.writestr('Payload/Wax.app/probe-build.json',json.dumps(manifest));z.writestr('Payload/Wax.app/WaxProbe.ipa',probe)
        return dict(xcode='fixture Xcode (not executed)',swift='fixture Swift (not executed)',sdk='fixture SDK (not executed)',xcodegen='fixture XcodeGen (not executed)')
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
            ipa=out/'Wax-Dev-1.0.ipa'
            self.rewrite(ipa, lambda entries: entries.update({'Payload/Wax.app/probe-build.json': b'{}'}))
            return result
        with self.assertRaises(ValueError):self.prepare(builder=missing,channel='dev')
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
        with self.assertRaises(ValueError):self.prepare(builder=mismatched,channel='dev')
        self.assertFalse(self.out.exists())

    def test_simulator_candidate_is_rejected_even_with_matching_version(self):
        def simulator(source,out,*args):
            result=self.build(source,out,*args);ipa=out/'Wax-1.0.ipa'
            with zipfile.ZipFile(ipa) as z:entries={n:z.read(n) for n in z.namelist()}
            key='Payload/Wax.app/Info.plist';info=plistlib.loads(entries[key]);info['CFBundleSupportedPlatforms']=['iPhoneSimulator'];entries[key]=plistlib.dumps(info)
            with zipfile.ZipFile(ipa,'w') as z:
                for name,data in entries.items():z.writestr(name,data)
            return result
        with self.assertRaises(ValueError):self.prepare(builder=simulator)
        self.assertFalse(self.out.exists())

    def test_accidental_credential_or_private_configuration_file_blocks_candidate(self):
        for name in ['accidental.P12','.env.production','embedded.mobileprovision','local.xcconfig']:
            def secret(source,out,*args):
                result=self.build(source,out,*args)
                with zipfile.ZipFile(out/'Wax-1.0.ipa','a') as z:z.writestr('Payload/Wax.app/'+name,b'PUBLIC TEST SENTINEL: not a real credential')
                return result
            with self.assertRaises(ValueError):self.prepare(builder=secret)
            self.assertFalse(self.out.exists())

    def rewrite(self, ipa, change):
        with zipfile.ZipFile(ipa) as z: entries={n:z.read(n) for n in z.namelist()}
        change(entries)
        with zipfile.ZipFile(ipa,'w') as z:
            for name,data in entries.items(): z.writestr(name,data)

    def test_standard_without_probe_produces_a_real_stage(self):
        report=self.prepare()
        self.assertIsNone(report['probe'])
        self.assertEqual(report['channel'],'standard')
        self.assertEqual(report['schemaVersion'],2)
        self.assertEqual(report['artifact']['bundleIdentifier'],'io.github.dylldev.wax')

    def test_channels_are_independent_of_both_feed_flavors(self):
        for channel in ('standard','dev'):
            for flavor in ('no-feed','configured-feed'):
                with self.subTest(channel=channel,flavor=flavor):
                    feed='https://public.example/feed.json' if flavor=='configured-feed' else ''
                    domain='loop.example' if flavor=='configured-feed' else ''
                    received=[]
                    def build(source,out,*args):
                        received.append(args)
                        return self.build(source,out,*args)
                    output=self.root/(channel+'-'+flavor)
                    report=self.prepare(channel=channel,flavor=flavor,feed=feed,domain=domain,output=output,builder=build)
                    expected='io.github.dylldev.wax'+('.dev' if channel=='dev' else '')
                    self.assertEqual(received,[(flavor,feed,domain,channel)])
                    self.assertEqual(report['channel'],channel)
                    self.assertEqual(report['artifact']['bundleIdentifier'],expected)
                    self.assertEqual(report['configuration']['flavor'],flavor)
                    self.assertEqual(report['probe'] is None,channel=='standard')
                    app=json.loads((output/'stage/apps.json').read_text())['apps'][0]
                    self.assertEqual(app['bundleIdentifier'],expected)
                    self.assertEqual(app['name'],'Wax Dev' if channel=='dev' else 'Wax')
                    staged=output/'stage'/report['artifact']['filename']
                    self.assertEqual(report['artifact']['sha256'],hashlib.sha256(staged.read_bytes()).hexdigest())

    def test_swapped_channel_identity_is_refused(self):
        for channel in ('standard','dev'):
            with self.subTest(channel=channel):
                def swapped(source,out,*args):
                    result=self.build(source,out,*args)
                    ipa=next(out.glob('*.ipa'))
                    def change(entries):
                        key='Payload/Wax.app/Info.plist';info=plistlib.loads(entries[key])
                        info['CFBundleIdentifier']='io.github.dylldev.wax' if channel=='dev' else 'io.github.dylldev.wax.dev'
                        entries[key]=plistlib.dumps(info)
                    self.rewrite(ipa,change);return result
                with self.assertRaisesRegex(ValueError,'metadata disagrees'):
                    self.prepare(channel=channel,builder=swapped)
                self.assertFalse(self.out.exists())

    def test_standard_refuses_either_dev_resource(self):
        for name in ('probe-build.json','WaxProbe.ipa'):
            with self.subTest(name=name):
                def injected(source,out,*args):
                    result=self.build(source,out,*args)
                    with zipfile.ZipFile(next(out.glob('*.ipa')),'a') as z:
                        z.writestr('Payload/Wax.app/Resources/'+name,b'public fixture sentinel')
                    return result
                with self.assertRaisesRegex(ValueError,'standard candidate contains Dev probe'):
                    self.prepare(builder=injected)
                self.assertFalse(self.out.exists())

    def test_dev_requires_each_probe_resource(self):
        for name in ('probe-build.json','WaxProbe.ipa'):
            with self.subTest(name=name):
                def missing(source,out,*args):
                    result=self.build(source,out,*args)
                    self.rewrite(next(out.glob('*.ipa')),lambda entries: entries.pop('Payload/Wax.app/'+name))
                    return result
                with self.assertRaisesRegex(ValueError,'Dev candidate requires'):
                    self.prepare(channel='dev',builder=missing)
                self.assertFalse(self.out.exists())

    def test_private_payload_gate_applies_to_dev_too(self):
        def secret(source,out,*args):
            result=self.build(source,out,*args)
            with zipfile.ZipFile(next(out.glob('*.ipa')),'a') as z:
                z.writestr('Payload/Wax.app/local.xcconfig',b'public fixture sentinel')
            return result
        with self.assertRaisesRegex(ValueError,'private configuration'):
            self.prepare(channel='dev',builder=secret)
        self.assertFalse(self.out.exists())

    def test_unknown_channel_is_refused_before_build(self):
        with self.assertRaisesRegex(ValueError,'unknown application channel'):
            self.prepare(channel='other',builder=lambda *_:self.fail('must not build'))

    def test_live_builder_forwards_channel_to_existing_script(self):
        for channel in ('standard','dev'):
            with self.subTest(channel=channel):
                with patch('prepare_release.subprocess.run') as run, patch('prepare_release.subprocess.check_output',return_value=b'fixture tool version'):
                    live_build(self.repo,self.root/'build','no-feed','','',channel)
                self.assertEqual(run.call_args.args[0],['bash',str(self.repo/'scripts/build-release-ipa.sh'),str(self.root/'build'),channel])
                self.assertTrue(run.call_args.kwargs['check'])

    def test_cli_forwards_channel_independently_of_feed_flavor(self):
        for channel in ('standard','dev'):
            for flavor in ('no-feed','configured-feed'):
                argv=['prepare_release.py','--repo',str(self.repo),'--tag','v1.0',
                      '--out',str(self.out),'--icon',str(self.icon),'--base-url','https://public.example/wax',
                      '--date','2026-11-05','--build','7','--flavor',flavor,'--channel',channel,'--no-history']
                with self.subTest(channel=channel,flavor=flavor), patch('prepare_release.prepare') as call, patch('sys.argv',argv), patch('builtins.print'):
                    main()
                    self.assertEqual(call.call_args.kwargs['channel'],channel)
                    self.assertEqual(call.call_args.args[7],flavor)

    def test_duplicate_payload_paths_are_refused_for_both_channels(self):
        for channel in ('standard','dev'):
            def duplicate(source,out,*args):
                result=self.build(source,out,*args)
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore',UserWarning)
                    with zipfile.ZipFile(next(out.glob('*.ipa')),'a') as z:
                        z.writestr('Payload/Wax.app/note.txt',b'first')
                        z.writestr('Payload/Wax.app/note.txt',b'second')
                return result
            with self.subTest(channel=channel), self.assertRaisesRegex(ValueError,'duplicate release archive paths'):
                self.prepare(channel=channel,builder=duplicate)
            self.assertFalse(self.out.exists())
