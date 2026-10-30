"""Source contract only; does not prove SwiftUI rendering or storage recovery."""
from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "App" / "SignView.swift"

class SignedSaveFeedbackTests(unittest.TestCase):
    def test_shelf_success_requires_saved_state_and_failure_offers_retry(self):
        text = SOURCE.read_text()
        self.assertTrue("if !failed { shelfSaveFeedback }" in text)
        start = text.index("@ViewBuilder private var shelfSaveFeedback")
        feedback = text[start:text.index("private var signedShelfLink", start)]
        self.assertIn("switch model.shelfSaveState", feedback)
        saved = feedback.index("case .saved:")
        failed = feedback.index("case .failed(let failure):")
        self.assertIn("signedShelfLink", feedback[saved:failed])
        self.assertNotIn("signedShelfLink", feedback[:saved] + feedback[failed:])
        self.assertIn("failure.localizedDescription", feedback[failed:])
        self.assertIn("model.retrySignedSave()", feedback[failed:])
        self.assertIn("case .saving:", feedback)
        self.assertIn("case .idle:", feedback)
        self.assertIn("exportButton(r)", text)

if __name__ == "__main__":
    unittest.main()
