import InstallKit
import SwiftUI
import UIKit

struct BugReportView: View {
    @EnvironmentObject private var reporter: ShakeReporter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let report = reporter.draft.text
        NavigationStack {
            Form {
                Section("What happened?") {
                    TextField("Describe the problem", text: $reporter.draft.whatHappened, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("What did you expect?") {
                    TextField("Describe what you expected", text: $reporter.draft.expectedBehavior, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Text(report)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    Text("Report preview")
                } footer: {
                    Text("Only the text above is shared. Do not include passwords, certificates or other private details. Nothing is sent until you choose an action below.")
                }
                Section {
                    Button {
                        UIPasteboard.general.string = report
                    } label: {
                        Label("Copy report", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: report) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: BugReport.issueURL(report: report)) {
                        Label("Open GitHub issue form", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        reporter.dismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}
