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
            list.append(WaxAction(icon: "square.and.arrow.up", title: "Export", share: library.url(for: entry)))
        }
        list.append(WaxAction(icon: "info.circle", title: "Details") { detail = entry })
        list.append(WaxAction(icon: "trash", title: "Delete", destructive: true) { library.remove(entry) })
        return list
    }

    private func row(_ e: LibraryEntry) -> some View {
        WaxRow(icon: e.kind == .unsigned ? "shippingbox" : "checkmark.seal", title: e.name,
               subtitle: [e.version.isEmpty ? nil : e.version,
                          ByteCountFormatter.string(fromByteCount: Int64(e.size), countStyle: .file),
                          e.added.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "),
               subtitleLines: 2) {
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

    /// Reads the picked file, then files it on the shelf its signature says it belongs on.
    private func add(_ url: URL) {
        adding = true
        problem = nil
        ImportLogs.shared.log("ipa: picked \(ImportLog.describe(url))")
        Task.detached {
            defer { discardPickerCopy(url) }
            do {
                let info = try IPAInspector.inspect(externalURL: url) { _ in }
                ImportLogs.shared.log("ipa: ok bundle=\(info.bundleIdentifier) version=\(info.version)")
                let name = info.displayName.isEmpty ? info.bundleIdentifier : info.displayName
                await library.fileNow(url, info: info)
                await MainActor.run {
                    router.shelf = info.hasCodeSignature ? .signed : .unsigned
                    AccessibilityNotification.Announcement(name.isEmpty ? "App added" : "Added \(name)").post()
                }
            } catch {
                let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ImportLogs.shared.log("ipa: failed \(ImportLog.describe(error))")
                await MainActor.run { problem = text }
            }
            await MainActor.run { adding = false }
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
