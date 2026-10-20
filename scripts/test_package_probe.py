import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

class ProbePackaging(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.app=self.root/'Built.app';self.source=self.root/'Source';self.out=self.root/'Out'
        self.app.mkdir();self.source.mkdir()
        self.info=dict(CFBundleIdentifier='io.github.dylldev.wax.probe',CFBundleShortVersionString='1.0',CFBundleVersion='1',CFBundleExecutable='WaxProbe',CFBundleURLTypes=[dict(CFBundleURLSchemes=['waxprobe'])],CFBundleSupportedPlatforms=['iPhoneOS'])
        self.plist=self.app/'Info.plist';self.write_info()
        (self.app/'WaxProbe').write_bytes(b'\xcf\xfa\xed\xfe'+b'fixture'*20);(self.app/'WaxProbe').chmod(0o755)
        (self.source/'WaxProbe.swift').write_text('// test source fixture\n')
    def write_info(self): self.plist.write_bytes(plistlib.dumps(self.info))
    def run_package(self):
        return subprocess.run([sys.executable,str(Path(__file__).with_name('package-probe.py')),'--app',str(self.app),'--source',str(self.source),'--out',str(self.out)],capture_output=True,text=True)
    def test_manifest_binds_actual_ipa_and_source_bytes(self):
        result=self.run_package();self.assertEqual(result.returncode,0,result.stderr)
        manifest=json.loads((self.out/'probe-build.json').read_text());ipa=self.out/'WaxProbe.ipa'
        self.assertEqual(manifest['ipaSHA256'],hashlib.sha256(ipa.read_bytes()).hexdigest())
        self.assertEqual(manifest['sources']['WaxProbe.swift'],hashlib.sha256((self.source/'WaxProbe.swift').read_bytes()).hexdigest())
        with zipfile.ZipFile(ipa) as z:
            self.assertEqual(z.read('Payload/WaxProbe.app/WaxProbe'),(self.app/'WaxProbe').read_bytes())
            self.assertEqual((z.getinfo('Payload/WaxProbe.app/WaxProbe').external_attr>>16)&0o777,0o755)
            self.assertIsNone(z.testzip())
    def test_invalid_metadata_preserves_an_existing_resource(self):
        self.out.mkdir();(self.out/'WaxProbe.ipa').write_bytes(b'previous')
        self.info['CFBundleIdentifier']='wrong.app';self.write_info()
        self.assertNotEqual(self.run_package().returncode,0)
        self.assertEqual((self.out/'WaxProbe.ipa').read_bytes(),b'previous')
    def test_unknown_scheme_is_not_bundled(self):
        self.info['CFBundleURLTypes'][0]['CFBundleURLSchemes'].append('other');self.write_info()
        self.assertNotEqual(self.run_package().returncode,0)
    def test_symlinks_are_rejected_without_reading_external_contents(self):
        outside=self.root/'outside';outside.write_text('not a resource')
        (self.app/'link').symlink_to(outside)
        self.assertNotEqual(self.run_package().returncode,0);self.assertFalse(self.out.exists())
    def test_fixed_inputs_produce_identical_probe_ipa_bytes(self):
        self.run_package();first=(self.out/'WaxProbe.ipa').read_bytes();self.run_package()
        self.assertEqual((self.out/'WaxProbe.ipa').read_bytes(),first)
    def test_missing_executable_and_unknown_source_files_are_refused(self):
        (self.app/'WaxProbe').unlink();self.assertNotEqual(self.run_package().returncode,0)
        (self.app/'WaxProbe').write_bytes(b'\xcf\xfa\xed\xfe');(self.app/'WaxProbe').chmod(0o755)
        (self.source/'private-token.txt').write_text('synthetic forbidden fixture')
        self.assertNotEqual(self.run_package().returncode,0)

if __name__=='__main__':unittest.main()
