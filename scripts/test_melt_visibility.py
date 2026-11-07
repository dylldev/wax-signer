"""The retained signing screen must pause its decorative animation off-tab."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MeltVisibility(unittest.TestCase):
    def test_signing_melt_receives_selected_tab_visibility(self):
        source = (ROOT / 'App/SignView.swift').read_text()
        calls = re.findall(r'WaxMelt\(([^\n]*)\)', source)
        self.assertTrue(calls, 'Signing must retain its progress illustration')
        for arguments in calls:
            self.assertRegex(arguments, r'isVisible:\s*router\.tab\s*==\s*\.sign')

    def test_timeline_pauses_for_visibility_scene_and_reduce_motion(self):
        source = (ROOT / 'App/WaxMelt.swift').read_text()
        self.assertRegex(source, r'private var animates: Bool\s*\{\s*isVisible\s*&&\s*scenePhase == \.active\s*&&\s*!reduceMotion\s*&&\s*progress < 1\s*\}')
        self.assertIn('paused: !animates', source)


if __name__ == '__main__':
    unittest.main()
