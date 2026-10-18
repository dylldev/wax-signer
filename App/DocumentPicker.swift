import IPAKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The system document picker in copy mode. The system downloads an iCloud file and hands back a local
/// copy in the app's temporary directory, so no security scope, coordination or placeholder handling is
/// needed to read it. Any file type can be chosen; content is validated afterwards.
struct DocumentPicker: UIViewControllerRepresentable {
    /// nil means the user cancelled.
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

enum ImportLogs {
    static let shared: ImportLog = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ImportLog(fileURL: caches.appendingPathComponent("wax-import.log"))
    }()
}

/// Deletes the picker's temporary copy once it has been read.
func discardPickerCopy(_ url: URL) {
    if url.path.hasPrefix(NSTemporaryDirectory()) || url.path.contains("/tmp/") {
        try? FileManager.default.removeItem(at: url)
    }
}

struct ImportLogView: View {
    @State private var lines: [String] = ImportLogs.shared.recentLines(60)

    var body: some View {
        List {
            Section {
                Text("Steps, error messages and file names only. No file contents or passwords are recorded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Recent events") {
                if lines.isEmpty { Text("Nothing recorded yet").foregroundStyle(.secondary) }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2.monospaced()).textSelection(.enabled)
                }
            }
            Section {
                Button("Refresh") { lines = ImportLogs.shared.recentLines(60) }
                Button("Clear", role: .destructive) { ImportLogs.shared.clear(); lines = [] }
            }
        }
        .navigationTitle("Import log")
        .navigationBarTitleDisplayMode(.inline)
    }
}
