"""Exercise the app build phase's resource boundary with real package output."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class BuildChannels(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'project.json'
            subprocess.run(['xcodegen', 'dump', '--type', 'json', '--file', str(output)], cwd=ROOT, check=True, capture_output=True)
            cls.spec = json.loads(output.read_text())
        cls.phase = cls.spec['targets']['LocalIPASigner']['postBuildScripts'][0]['script']

    def package(self, development, stale=False):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            app = base / 'WaxProbe.app'
            app.mkdir()
            info = dict(CFBundleIdentifier='io.github.dylldev.wax.probe', CFBundleShortVersionString='1.0', CFBundleVersion='1', CFBundleExecutable='WaxProbe', CFBundleURLTypes=[dict(CFBundleURLSchemes=['waxprobe'])])
            (app / 'Info.plist').write_bytes(plistlib.dumps(info))
            binary = app / 'WaxProbe'
            binary.write_bytes(b'\xcf\xfa\xed\xfe' + b'fixture' * 20)
            binary.chmod(0o755)
            out = base / 'Wax.app'
            out.mkdir()
            if stale:
                (out / 'WaxProbe.ipa').write_bytes(b'stale')
                (out / 'probe-build.json').write_text('{}')
            env = dict(os.environ, PROJECT_DIR=str(ROOT), BUILT_PRODUCTS_DIR=str(base), TARGET_BUILD_DIR=str(base), UNLOCALIZED_RESOURCES_FOLDER_PATH='Wax.app', WAX_DEVELOPMENT='YES' if development else 'NO')
            result = subprocess.run(['bash', '-e', '-c', self.phase], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return {path.name for path in out.iterdir()}

    def test_standard_build_contains_no_probe(self):
        self.assertFalse({'WaxProbe.ipa', 'probe-build.json'} & self.package(False))

    def test_standard_build_removes_stale_developer_resources(self):
        self.assertFalse({'WaxProbe.ipa', 'probe-build.json'} & self.package(False, stale=True))

    def test_dev_build_keeps_source_built_probe(self):
        self.assertTrue({'WaxProbe.ipa', 'probe-build.json'} <= self.package(True))

    def test_invalid_channel_fails_before_build(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/build-release-ipa.sh'), '/dev/null', 'typo'], env=dict(os.environ, PATH='/usr/bin:/bin'), capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('standard|dev', result.stderr)

    def release(self, channel, prefix, configuration, scheme):
        # Replace only Xcode's slow compiler. Packaging and checksum generation run for real.
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            commands = base / 'bin'
            commands.mkdir()
            (commands / 'xcodegen').write_text('#!/bin/bash\nexit 0\n')
            builder = commands / 'xcodebuild'
            builder.write_text('''#!/usr/bin/python3
import os, pathlib, plistlib, sys
args = sys.argv[1:]
value = lambda flag: args[args.index(flag) + 1]
assert value('-configuration') == os.environ['EXPECTED_CONFIGURATION']
assert value('-scheme') == os.environ['EXPECTED_SCHEME']
app = pathlib.Path(value('-derivedDataPath')) / 'Build/Products' / (value('-configuration') + '-iphoneos') / 'LocalIPASigner.app'
app.mkdir(parents=True)
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.2.3'}))
(app / 'LocalIPASigner').write_bytes(b'compiled app fixture')
''')
            for command in commands.iterdir():
                command.chmod(0o755)
            env = dict(os.environ, PATH=str(commands) + ':/usr/bin:/bin', EXPECTED_CONFIGURATION=configuration, EXPECTED_SCHEME=scheme, WAX_DEFAULT_FEED='', WAX_INSTALL_DOMAIN='')
            out = base / 'output with spaces'
            args = ['bash', str(ROOT / 'scripts/build-release-ipa.sh'), str(out)]
            if channel:
                args.append(channel)
            result = subprocess.run(args, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            name = prefix + '-1.2.3.ipa'
            ipa = out / name
            with zipfile.ZipFile(ipa) as archive:
                self.assertEqual(archive.read('Payload/LocalIPASigner.app/LocalIPASigner'), b'compiled app fixture')
            self.assertEqual((out / (name + '.sha256')).read_text(), hashlib.sha256(ipa.read_bytes()).hexdigest() + '  ' + name + '\n')

    def test_default_download_uses_standard_release_and_filename(self):
        self.release(None, 'Wax', 'Release', 'LocalIPASigner')

    def test_dev_download_uses_development_and_distinct_filename(self):
        self.release('dev', 'Wax-Dev', 'Development', 'WaxDev')


if __name__ == '__main__':
    unittest.main()
