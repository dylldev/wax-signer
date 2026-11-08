import InstallKit
import SigningKit
import SwiftUI

#if WAX_DEVELOPMENT
struct DeveloperSettingsView: View {
    @EnvironmentObject private var model: SigningModel
    @EnvironmentObject private var ota: OTAInstallModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WaxPanel {
                    NavigationLink { SigningOptionsView(model: model, showDeveloperTools: true) } label: {
                        WaxListRow(icon: "slider.horizontal.3", title: "Advanced signing") { WaxChevron() }
                    }
                    WaxRowDivider()
                    NavigationLink { CredentialsView(showDeveloperTools: true) } label: {
                        WaxListRow(icon: "testtube.2", title: "Certificate tests") { WaxChevron() }
                    }
                    WaxRowDivider()
                    NavigationLink { MeltDemo(progress: 0.35) } label: {
                        WaxListRow(icon: "flame", title: "Animation preview") { WaxChevron() }
                    }
                    WaxRowDivider()
                    NavigationLink { ImportLogView() } label: {
                        WaxListRow(icon: "doc.text.magnifyingglass", title: "Import log") { WaxChevron() }
                    }
                }
                .buttonStyle(WaxRowButtonStyle())
                Button("Prepare signing preview") {
                    model.discardPreflight()
                    model.sign(reviewBeforeSigning: true)
                }
                .buttonStyle(WaxSecondaryButtonStyle())
                .disabled(!model.canSign)
                if model.busyMessage != nil { ProgressView("Preparing…") }
                if model.passportReport != nil { passportCard }
                if let error = model.errorText { WaxFeedbackCard(tone: .bad, text: error) }
            }
            .padding(.horizontal, Wax.inset)
            .padding(.bottom, 24)
        }
        .background(Wax.bg.ignoresSafeArea())
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var passportFindings: [PreflightFinding] {
        guard let report = model.passportReport else { return [] }
        let route = PreflightFinding(
            id: "install-host", status: ota.isConfigured ? .pass : .warning,
            title: ota.isConfigured ? "Install host is configured" : "Install host needs setup",
            detail: ota.isConfigured ? "Wax is set up to use \(ota.hostSummary)." : "Set up an install host before installing from Wax.",
            evidence: "This checks setup only. It does not prove the host is reachable or that iOS will accept the app."
        )
        let reachability = PreflightFinding(id: "host-reachability", status: .unknown,
                                           title: "Install host reachability is unknown",
                                           detail: "Run the host check in Settings to test the connection. A connection does not prove iOS will accept the app.")
        return report.findings + [route, reachability]
    }

    private var passportCard: some View {
        WaxPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Signing preview")
                    .font(.headline).foregroundStyle(Wax.text)
                Text("Wax checks these inputs before signing. Only iOS can make the final install decision.")
                    .font(.footnote).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
                ForEach(passportFindings) { finding in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finding.detail).foregroundStyle(Wax.sub)
                            if !finding.evidence.isEmpty {
                                Text(finding.evidence).foregroundStyle(Wax.sub)
                            }
                        }
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: findingSymbol(finding.status))
                                .foregroundStyle(findingColor(finding.status))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(finding.title).font(.subheadline.weight(.medium)).foregroundStyle(Wax.text)
                                Text(finding.status.rawValue.capitalized).font(.caption).foregroundStyle(findingColor(finding.status))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .tint(Wax.link)
                    .multilineTextAlignment(.leading)       // a disclosure label centres wrapped lines otherwise
                }
                Button("Discard check") { model.discardPreflight() }
                    .font(.footnote.weight(.semibold)).foregroundStyle(Wax.link)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func findingSymbol(_ status: PreflightStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func findingColor(_ status: PreflightStatus) -> Color {
        switch status {
        case .pass: Wax.ok
        case .warning: Wax.warn
        case .blocked: Wax.bad
        case .unknown: Wax.sub
        }
    }

}
#endif
