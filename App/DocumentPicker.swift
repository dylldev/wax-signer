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

/// Deletes only an app-owned temporary copy. A path component named "tmp" is not ownership evidence.
/// Resolve parents for iOS /var/private aliases, but never authorize deletion via a leaf symlink.
func discardPickerCopy(_ url: URL, within temporaryRoot: URL = FileManager.default.temporaryDirectory) {
    guard url.isFileURL, temporaryRoot.isFileURL else { return }
    let root = temporaryRoot.resolvingSymlinksInPath().standardizedFileURL
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
    guard parent.path == root.path || parent.path.hasPrefix(root.path + "/") else { return }
    let candidate = parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL
    guard candidate.path.hasPrefix(root.path + "/"),
          let values = try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true else { return }
    try? FileManager.default.removeItem(at: candidate)
}

struct ImportLogView: View {
    @State private var lines: [String] = ImportLogs.shared.recentLines(60)
    @State private var confirmClear = false

    var body: some View {
        List {
            Section {
                Text("Steps, error messages and file names only. No file contents or passwords are recorded.")
                    .font(.footnote).foregroundStyle(Wax.sub)
            }
            .listRowBackground(Wax.card)
            Section("Recent events") {
                if lines.isEmpty { Text("Nothing recorded yet").foregroundStyle(Wax.sub) }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2.monospaced()).foregroundStyle(Wax.text).textSelection(.enabled)
                }
            }
            .listRowBackground(Wax.card)
        }
        .scrollContentBackground(.hidden)
        .background(Wax.bg.ignoresSafeArea())
        .navigationTitle("Import log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Wax.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Refresh", systemImage: "arrow.clockwise") { lines = ImportLogs.shared.recentLines(60) }
                    Button("Clear log", systemImage: "trash", role: .destructive) { confirmClear = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Import log actions")
            }
        }
        .confirmationDialog("Clear the import log?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear log", role: .destructive) { ImportLogs.shared.clear(); lines = [] }
        } message: { Text("This removes the recent import steps and errors saved on this phone.") }
    }
}
