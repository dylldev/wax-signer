import hashlib
import json
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).parent
BASE = 'https://dylldev.github.io/wax'


def icon(path):
    def chunk(kind, data): return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB',1024,1024,8,2,0,0,0)) + chunk(b'IDAT', zlib.compress((b'\0'+b'\x88\x22\x11'*1024)*1024)) + chunk(b'IEND', b''))


class ReleaseIntegrity(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name); self.ipa = self.root / 'Wax 1&2.ipa'; self.out = self.root / 'dist'
        with zipfile.ZipFile(self.ipa, 'w') as z:
            z.writestr('Payload/Wax.app/Info.plist', plistlib.dumps(dict(CFBundleIdentifier='io.github.dylldev.wax',CFBundleShortVersionString='1.0',CFBundleVersion='123',MinimumOSVersion='17.0')))
        self.icon = self.root / 'icon.png'; icon(self.icon)
        for name in ('LICENSE','NOTICE'): (self.root / name).write_text(name)
    def generate(self, *args, ipa=None, out=None):
        return subprocess.run([sys.executable,str(HERE/'make_source.py'),'--ipa',str(ipa or self.ipa),'--icon',str(self.icon),'--capabilities','signer-export','--date','2026-10-19','--base-url',BASE,'--out',str(out or self.out),'--extra',str(self.root/'LICENSE'),'--extra',str(self.root/'NOTICE'),*args],capture_output=True,text=True)
    def validate(self):
        return subprocess.run([sys.executable,str(HERE/'validate_source.py'),'--dir',str(self.out),'--expect-base',BASE],capture_output=True,text=True)
    def test_real_metadata_hash_encoded_url_and_offline_interoperability(self):
        self.assertEqual(self.generate().returncode,0)
        source=json.loads((self.out/'apps.json').read_text()); app=source['apps'][0]; v=app['versions'][0]
        self.assertEqual(v['sha256'],hashlib.sha256(self.ipa.read_bytes()).hexdigest())
        self.assertEqual(v['downloadURL'],BASE+'/Wax%201%262.ipa')
        self.assertNotIn('does not sign',app['localizedDescription'])
        result=self.validate();self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('url=https%3A%2F%2Fdylldev.github.io%2Fwax%2Fapps.json',(self.out/'index.html').read_text())
    def test_artifact_corruption_fails_checksum_gate(self):
        self.generate();(self.out/self.ipa.name).write_bytes(b'wrong')
        self.assertNotEqual(self.validate().returncode,0)
    def test_missing_input_never_creates_feed(self):
        self.assertNotEqual(self.generate(ipa=self.root/'missing.ipa').returncode,0);self.assertFalse(self.out.exists())
    def test_nonempty_stage_is_not_overwritten(self):
        self.out.mkdir();(self.out/'valuable').write_text('keep')
        self.assertNotEqual(self.generate().returncode,0);self.assertEqual((self.out/'valuable').read_text(),'keep')
    def test_generation_is_reproducible_for_fixed_inputs_and_date(self):
        self.generate();other=self.root/'second';self.generate(out=other)
        self.assertEqual((self.out/'apps.json').read_bytes(),(other/'apps.json').read_bytes())
        self.assertEqual((self.out/'index.html').read_bytes(),(other/'index.html').read_bytes())
    def test_missing_history_artifact_is_not_advertised(self):
        self.generate();feed=self.out/'apps.json';data=json.loads(feed.read_text());data['apps'][0]['versions'][0]['downloadURL']=BASE+'/missing.ipa';feed.write_text(json.dumps(data))
        out=self.root/'next';result=self.generate('--keep-versions',str(feed),out=out)
        self.assertNotEqual(result.returncode,0);self.assertFalse(out.exists())
    def test_malformed_schema_fails_without_traceback(self):
        self.generate();(self.out/'apps.json').write_text(json.dumps({'apps':[None,'wrong',{}]}))
        result=self.validate();self.assertNotEqual(result.returncode,0);self.assertNotIn('Traceback',result.stderr)
    def test_legacy_fields_cannot_disagree_with_latest(self):
        self.generate();feed=self.out/'apps.json';data=json.loads(feed.read_text());data['apps'][0]['version']='0.0';feed.write_text(json.dumps(data))
        self.assertNotEqual(self.validate().returncode,0)
