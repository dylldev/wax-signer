import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile


class MakeSourceTests(unittest.TestCase):
    def test_untrusted_values_are_escaped_in_the_landing_page(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = os.path.join(directory, 'app"><img src=x onerror=alert(1)>.ipa')
            out = os.path.join(directory, "dist")
            info = {
                "CFBundleIdentifier": "com.example.app",
                "CFBundleShortVersionString": "1</p><script>alert(2)</script>",
                "CFBundleVersion": "2</p><script>alert(3)</script>",
                "CFBundleName": "Example",
            }
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Example.app/Info.plist", plistlib.dumps(info))

            base = 'https://example.test/"><script>alert(4)</script><a href="'
            subprocess.run(
                [sys.executable, os.path.join(os.path.dirname(__file__), "make_source.py"),
                 "--ipa", ipa, "--base-url", base, "--out", out],
                check=True, capture_output=True, text=True,
            )

            with open(os.path.join(out, "index.html"), encoding="utf-8") as page_file:
                page = page_file.read()
            self.assertNotIn("<script", page.lower())
            self.assertNotIn("<img src=x", page.lower())
            self.assertNotIn("onerror=", page.lower())


if __name__ == "__main__":
    unittest.main()
