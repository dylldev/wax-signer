import json
import os
import subprocess
import sys
import tempfile
import unittest


class ValidateSourceTests(unittest.TestCase):
    def test_offline_validation_rejects_encoded_path_traversal(self):
        with tempfile.TemporaryDirectory() as parent:
            stage = os.path.join(parent, "stage")
            os.mkdir(stage)
            with open(os.path.join(parent, "secret"), "w") as f:
                f.write("outside staged directory")
            base = "https://example.test/stage"
            with open(os.path.join(stage, "apps.json"), "w") as f:
                json.dump({"apps": [{"bundleIdentifier": "example.app", "iconURL": base + "/%2e%2e/secret", "versions": []}]}, f)

            result = subprocess.run(
                [sys.executable, "Source/validate_source.py", "--dir", stage, "--expect-base", base],
                capture_output=True, text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("icon URL -> 0", result.stdout)

    def test_remote_validation_rejects_file_urls(self):
        with tempfile.NamedTemporaryFile("w", encoding="utf-8") as source:
            json.dump({"apps": []}, source)
            source.flush()
            result = subprocess.run(
                [sys.executable, "Source/validate_source.py", "file://" + source.name],
                capture_output=True, text=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("-> 0", result.stdout)
        self.assertNotIn("-> 200", result.stdout)


if __name__ == "__main__":
    unittest.main()
