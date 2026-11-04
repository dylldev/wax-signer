"""Source contract only; UI dialog presentation still requires simulator checks."""
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "App" / "ContentView.swift"

class IPADeleteConfirmationTests(unittest.TestCase):
    def test_delete_action_requests_named_confirmation_before_removal(self):
        text = SOURCE.read_text()
        self.assertTrue('@State private var entryToDelete: LibraryEntry?' in text)
        start = text.index('private func actions(for entry: LibraryEntry)')
        actions = text[start:text.index('private func row(', start)]
        self.assertTrue('entryToDelete = entry' in actions)
        self.assertFalse('library.remove(entry)' in actions)
        self.assertTrue('Delete “\\(entryToDelete?.name ?? "this IPA")”?' in text)
        self.assertTrue('Button("Delete IPA", role: .destructive)' in text)
        self.assertTrue('Button("Cancel", role: .cancel)' in text)
        self.assertTrue('This removes Wax\'s saved IPA file. It does not remove an app installed on your iPhone.' in text)
        self.assertTrue('await library.remove(entry)' in text)

if __name__ == "__main__":
    unittest.main()
