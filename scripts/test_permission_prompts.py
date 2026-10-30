"""Only the explicit Enable notifications action may show the iOS permission alert."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PermissionPrompts(unittest.TestCase):
    def test_only_the_enable_button_path_asks_for_notification_permission(self):
        # Signing, installing and reminders must never open the iOS permission alert on their own.
        callers = sorted(str(path.relative_to(ROOT)) for path in (ROOT / 'App').rglob('*.swift') if 'requestAuthorization' in path.read_text())
        self.assertEqual(callers, ['App/NotificationPermissionModel.swift'])


if __name__ == '__main__':
    unittest.main()
