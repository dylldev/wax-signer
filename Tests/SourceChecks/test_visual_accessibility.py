"""Source policy checks; these do not verify rendered SwiftUI accessibility."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def component(file, name):
    source = (ROOT / 'App' / file).read_text()
    return source.split(f'struct {name}', 1)[1].split('\nstruct ', 1)[0]


class VisualAccessibilitySourceTests(unittest.TestCase):
    def assert_motion_policy(self, source):
        self.assertIn('@Environment(\\.accessibilityReduceMotion)', source)
        self.assertRegex(source, r'\.scaleEffect\([^\n]*reduceMotion[^\n]*\)')
        self.assertRegex(source, r'\.animation\(reduceMotion \? nil :')

    def test_grouped_rows_stack_at_accessibility_sizes(self):
        source = component('Theme.swift', 'WaxListRow')
        self.assertIn('@Environment(\\.dynamicTypeSize)', source)
        self.assertIn('dynamicTypeSize.isAccessibilitySize', source)
        self.assertIn('AnyLayout(VStackLayout(alignment: .leading', source)
        self.assertIn('AnyLayout(HStackLayout(spacing: Wax.Space.m))', source)
        self.assertIn('layout {', source)

    def test_primary_press_obeys_reduce_motion(self):
        self.assert_motion_policy(component('Theme.swift', 'WaxPrimaryButtonStyle'))

    def test_tab_press_obeys_reduce_motion(self):
        self.assert_motion_policy(component('WaxTabBar.swift', 'TabPressStyle'))

    def test_status_pill_can_grow_with_text(self):
        source = component('Theme.swift', 'WaxPill')
        self.assertNotRegex(source, r'\.frame\(height:')
        self.assertRegex(source, r'\.frame\(minHeight:\s*26\)')

    def test_tab_labels_remain_visible_at_accessibility_sizes(self):
        source = component('WaxTabBar.swift', 'WaxTabBar')
        self.assertNotIn('if !dynamicTypeSize.isAccessibilitySize', source)
        self.assertIn('Text(item.title)', source)
        self.assertNotRegex(source, r'Text\(item.title\)[^\n]*\.lineLimit\(1\)')
        self.assertRegex(source, r'\.fixedSize\(horizontal: false, vertical: true\)')


if __name__ == '__main__':
    unittest.main(verbosity=2)
