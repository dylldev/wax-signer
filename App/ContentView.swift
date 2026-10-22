import InstallKit
import IPAKit
import SwiftUI

/// The IPA tab: Wax's shelf. Unsigned apps wait to be signed; signed ones Wax made wait to be exported.
struct ContentView: View {
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var signing: SigningModel
    @State private var importing = false
    @State private var adding = false
    @State private var problem: String?
    @State private var detail: LibraryEntry?
    @State private var retryImport: URL?
    @State private var retryPending: UUID?
    @State private var confirmRepair = false

    @State private var actionEntry: LibraryEntry?
    @State private var afterSheet: (() -> Void)?

    /// Which shelf this tab shows. It lives on the router so another screen can send the person here.
    private var shelf: LibraryEntry.Kind { router.shelf }
    private var entries: [LibraryEntry] { shelf == .unsigned ? library.unsigned : library.signed }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    WaxHeader(title: "IPA", subtitle: "Your apps, before and after signing.").id("top")
                    Picker("Shelf", selection: $router.shelf) {
                        Text("Unsigned").tag(LibraryEntry.Kind.unsigned)
                        Text("Signed").tag(LibraryEntry.Kind.signed)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if shelf == .unsigned { addRow }
                    if let problem { WaxFeedbackCard(tone: .bad, text: problem) }
                    if let message = library.message { WaxFeedbackCard(tone: .bad, text: message) }
                    if let retryImport {
                        Button("Retry Save") { add(retryImport, pending: retryPending) }.buttonStyle(WaxSecondaryButtonStyle()).disabled(adding)
                        ShareLink("Export retained IPA", item: retryImport)
                    }
                    if library.message != nil {
                        Button("Retry recovery / cleanup") { Task { await library.refresh() } }.buttonStyle(WaxSecondaryButtonStyle())
                        Button("Recover Library Index") { confirmRepair = true }.font(.footnote)
                    }
                    ForEach(library.recovery) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Retained: \(item.name)").font(.subheadline)
                            HStack {
                                Button("Retry Save") { Task { do { _ = try await library.retry(item) } catch { problem = error.localizedDescription } } }
                                    .disabled(library.busy)
                                ShareLink("Export", item: item.url)
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius))
                    }
                    if entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(entries) { entry in
                            Button { actionEntry = entry } label: { row(entry) }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Wax.inset)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Wax.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: router.reselectTick[.ipa]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            .onChange(of: problem) { _, new in if let new { AccessibilityNotification.Announcement(new).post() } }
            }
            .waxMotion(value: shelf)
        }
        .confirmationDialog("Recover the library index?", isPresented: $confirmRepair, titleVisibility: .visible) {
            Button("Recover Library Index") { Task { await library.repairIndex() } }
        } message: { Text("Wax keeps a copy of the damaged index and all IPA files. Unrecognized artifacts are recovered with unknown provenance; nothing is deleted.") }
        .sheet(isPresented: $importing) {
            DocumentPicker { picked in
                importing = false
                guard let picked else { ImportLogs.shared.log("ipa: picker cancelled"); return }
                add(picked)
            }
        }
        .sheet(item: $detail) { entry in IPADetailSheet(entry: entry) }
        .sheet(item: $actionEntry, onDismiss: { let run = afterSheet; afterSheet = nil; run?() }) { entry in
            WaxActionSheet(title: entry.name, subtitle: entry.version.isEmpty ? "" : "Version \(entry.version)",
                           actions: actions(for: entry)) { then in afterSheet = then; actionEntry = nil }
                .presentationDetents([.height(CGFloat(160 + 66 * actions(for: entry).count))])
                .presentationDragIndicator(.visible)
                .presentationBackground(Wax.bg)
        }
    }

    private var addRow: some View {
        Button { ImportLogs.shared.log("ipa: add tapped"); importing = true } label: {
            WaxRow(icon: "plus", title: adding ? "Adding…" : "Add an IPA", subtitle: "Pick one from Files") {
                if adding { ProgressView() } else { WaxLinkText(text: "Add") }
            }
        }
        .buttonStyle(.plain)
        .disabled(adding)
    }

    private func actions(for entry: LibraryEntry) -> [WaxAction] {
        var list: [WaxAction] = []
        if entry.kind == .unsigned {
            list.append(WaxAction(icon: "checkmark.seal", title: "Sign") { signing.use(entry); router.tab = .sign })
        } else {
            list.append(WaxAction(icon: "arrow.triangle.2.circlepath", title: "Re-sign") { signing.use(entry); router.tab = .sign })
            list.append(WaxAction(icon: "square.and.arrow.up", title: "Export", share: library.url(for: entry)))
        }
        list.append(WaxAction(icon: "info.circle", title: "Details") { detail = entry })
        list.append(WaxAction(icon: "trash", title: "Delete", destructive: true) { Task { await library.remove(entry) } })
        return list
    }

    private func row(_ e: LibraryEntry) -> some View {
        WaxRow(icon: e.kind == .unsigned ? "shippingbox" : "checkmark.seal", title: e.name,
               subtitle: [e.version.isEmpty ? nil : e.version, e.build.map { "Build " + $0 },
                          ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file),
                          e.added.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "),
               subtitleLines: 2) {
            if e.kind == .signed { SignedExpiryPill(url: library.url(for: e)) }
            Image(systemName: "ellipsis").font(.footnote.weight(.bold)).foregroundStyle(Wax.sub)
        }
    }

    @ViewBuilder private var emptyState: some View {
        if shelf == .unsigned {
            WaxEmptyState(title: "No unsigned apps yet",
                          message: "Add an IPA from Files, or sign one from the Sign tab. It lands here.",
                          actionTitle: "Go to Sign") { router.tab = .sign }
        } else {
            WaxEmptyState(title: "Nothing signed yet",
                          message: "Apps Wax signs land here, ready to export.",
                          actionTitle: "Go to Sign") { router.tab = .sign }
        }
    }

    /// Only the awaited commit earns an Added announcement. A publisher's signature is not Wax provenance.
    private func add(_ url: URL, pending: UUID? = nil) {
        adding = true; problem = nil
        Task {
            defer { adding = false }
            do {
                let saved: LibrarySaveResult
                if let pending { saved = try await library.retryImport(pending) }
                else { saved = try await library.importPicked(url) }
                retryImport = nil; retryPending = nil; router.shelf = .unsigned
                _ = saved // The model announces only a confirmed commit.
            } catch {
                retryImport = (error as? ShelfSaveFailure)?.artifact ?? url
                retryPending = (error as? ShelfSaveFailure)?.pendingID ?? pending
                problem = error.localizedDescription
            }
        }
    }

}

/// What is inside one app file, read from the shelf copy.
struct IPADetailSheet: View {
    let entry: LibraryEntry
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var result: Result<IPAMetadata, IPAError>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    switch result {
                    case .success(let m): metadata(m)
                    case .failure(let e): Text(e.localizedDescription).font(.footnote).foregroundStyle(Wax.bad)
                    case nil: ProgressView().padding(.top, 40)
                    }
                }
                .padding(.horizontal, Wax.inset)
            }
            .background(Wax.bg.ignoresSafeArea())
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            let url = library.url(for: entry)
            result = await Task.detached { Result { try IPAInspector.inspect(url: url) }.mapError { ($0 as? IPAError) ?? .unreadable("\($0)") } }.value
        }
    }

    @ViewBuilder private func metadata(_ m: IPAMetadata) -> some View {
        WaxSectionLabel(text: "App")
        WaxPanel {
            WaxKV(key: "Name", value: m.displayName.isEmpty ? "—" : m.displayName)
            WaxDivider()
            WaxKV(key: "Bundle ID", value: m.bundleIdentifier)
            WaxDivider()
            WaxKV(key: "Version", value: m.version.isEmpty ? "—" : m.version)
            WaxDivider()
            WaxKV(key: "Build", value: m.build.isEmpty ? "—" : m.build)
            WaxDivider()
            WaxKV(key: "Minimum iOS", value: m.minimumOSVersion ?? "—")
            WaxDivider()
            WaxKV(key: "Executable", value: m.executable)
        }
        WaxSectionLabel(text: "Archive")
        WaxPanel {
            WaxKV(key: "Origin", value: entry.provenance?.rawValue ?? "Unknown (legacy entry)")
            WaxDivider()
            if let hash = entry.sha256 {
                Text("IPA SHA-256: " + hash).font(.caption.monospaced()).textSelection(.enabled)
                WaxDivider()
            }
            WaxKV(key: "Entries", value: "\(m.entryCount)")
            WaxDivider()
            WaxKV(key: "Code signature", value: m.hasCodeSignature ? "Present" : "None")
            WaxDivider()
            WaxKV(key: "Embedded profile", value: m.hasEmbeddedProfile ? "Present" : "None")
        }
        Text("Wax reads the archive's structure. It can't tell you whether the signature or profile is valid, or whether iOS will accept the app.")
            .font(.footnote).foregroundStyle(Wax.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 24)
    }
}


/// "Expires in 3 days" for a signed app, read from the profile inside its own file. Shows nothing when that cannot be read.
struct SignedExpiryPill: View {
    let url: URL
    @State private var status: SignedAppExpiry = .unknown

    var body: some View {
        Group {
            if let label = status.label {
                WaxPill(text: label, tone: status.severity == .bad ? .bad : (status.severity == .warn ? .warn : .ok))
            }
        }
        .task(id: url) {
            let file = url
            // Keyed by path and modification date: a signed file never changes in place, so each one is read once.
            let key = file.path + "@" + String((try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0)
            let expiration: Date?
            if let cached = Self.expirations[key] { expiration = cached } else {
                expiration = await Task.detached(priority: .utility) { try? IPAInspector.inspect(url: file).embeddedProfileExpiration }.value
                Self.expirations[key] = .some(expiration)
            }
            guard !Task.isCancelled else { return }        // task(id:) cancels this read when the row's file changes
            status = SignedAppExpiry.status(expiration: expiration)
        }
    }

    @MainActor private static var expirations: [String: Date?] = [:]
}
