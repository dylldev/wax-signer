import SourcesKit
import SwiftUI
import UIKit

/// Sources: places the user adds (a source file's address, or a link to one IPA) and the apps they offer.
struct SourcesView: View {
    @EnvironmentObject private var model: SourcesModel
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var signing: SigningModel
    @EnvironmentObject private var router: Router
    @AppStorage("signAfterDownload") private var signAfterDownload = false
    @State private var draft = ""
    @State private var actionSource: SavedSource?
    @State private var afterSheet: (() -> Void)?
    /// Shown under the address field when Paste had nothing to give.
    @State private var pasteNote: String?
    @FocusState private var addFocused: Bool

    var body: some View {
        NavigationStack(path: $router.sourcesPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        WaxHeader(title: "Sources", subtitle: "Apps from places you add.").id("top")
                        addCard
                        if let m = model.message { WaxFeedbackCard(tone: .bad, text: m) }
                        if model.sources.isEmpty { emptyState } else {
                            ForEach(model.sources) { source in
                                NavigationLink(value: source.id) { row(source) }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in actionSource = source })
                                    // The options button sits on top of the row, not inside the link's label, so a tap
                                    // opens the actions instead of following the link, and VoiceOver finds it as its own control.
                                    .overlay(alignment: .trailing) {
                                        if !model.loading.contains(source.id) {
                                            Button { actionSource = source } label: {
                                                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(Wax.sub)
                                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Options for \(source.name)")
                                            .padding(.trailing, 30)
                                        }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, Wax.inset)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.refreshAll() }
                .background(Wax.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: router.reselectTick[.sources]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
                .onChange(of: model.message) { _, new in if let new { AccessibilityNotification.Announcement(new).post() } }
                .onChange(of: draft) { _, _ in pasteNote = nil }
            }
            .navigationDestination(for: UUID.self) { id in SourceAppsView(sourceID: id) }
        }
        .sheet(item: $actionSource, onDismiss: { let run = afterSheet; afterSheet = nil; run?() }) { source in
            WaxActionSheet(title: source.name, subtitle: "\(source.appCount) apps", actions: [
                WaxAction(icon: "arrow.clockwise", title: "Refresh") { model.refresh(source.id) },
                WaxAction(icon: "trash", title: "Remove", destructive: true) { model.remove(source.id) },
            ]) { then in afterSheet = then; actionSource = nil }
                .presentationDetents([.height(CGFloat(160 + 66 * 2))])
                .presentationDragIndicator(.visible)
                .presentationBackground(Wax.bg)
        }
    }

    /// One card: what you are adding, the accent Add capsule, and the address field with a Paste button.
    private var addCard: some View {
        WaxPanel {
            HStack(spacing: 12) {
                WaxIconTile(symbol: "link.badge.plus")
                Text("Add a source").font(.callout.weight(.semibold)).foregroundStyle(Wax.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                addCapsule
            }
            .frame(minHeight: Wax.touch)
            .padding(.vertical, Wax.Space.xs)
            WaxDivider()
            HStack(spacing: Wax.Space.s) {
                TextField("Address of a source file or IPA", text: $draft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(.subheadline).foregroundStyle(Wax.text)
                    .submitLabel(.go).onSubmit(add)
                    .focused($addFocused)
                pasteButton
            }
            .frame(minHeight: Wax.touch)
            .padding(.vertical, Wax.Space.xs)
            if let pasteNote {
                Text(pasteNote).font(.footnote).foregroundStyle(Wax.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Wax.Space.s)
                    .accessibilityLabel(pasteNote)
            }
        }
    }

    /// Accent while there is something to add, dimmed but still the same button when there is not.
    private var addCapsule: some View {
        Button(action: add) {
            Text("Add")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canAdd ? Wax.onAccent : Wax.sub)
                .padding(.horizontal, 18)
                .frame(minHeight: Wax.touch)
                .background(Wax.accent.opacity(canAdd ? 1 : 0.22), in: Capsule())
                .overlay(Capsule().stroke(Wax.line, lineWidth: canAdd ? 0 : 1))
        }
        .buttonStyle(.plain)
        .disabled(!canAdd)
        .accessibilityLabel("Add this source")
    }

    private var pasteButton: some View {
        Button(action: paste) {
            Label("Paste", systemImage: "doc.on.clipboard")
                .labelStyle(.titleAndIcon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Wax.link)
                .padding(.horizontal, Wax.Space.m)
                .frame(minHeight: Wax.touch)
                .background(Wax.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste an address from the clipboard")
    }

    private var canAdd: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func add() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        addFocused = false
        pasteNote = nil
        model.add(draft, signAfter: signAfterDownload, library: library, signing: signing, router: router)
        if URL(string: draft.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme == "https" { draft = "" }
    }

    /// Fills the field from the clipboard. It never adds on its own: the person still taps Add.
    private func paste() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            pasteNote = "There is nothing on your clipboard."
            return
        }
        pasteNote = nil
        draft = text
    }

    private func row(_ s: SavedSource) -> some View {
        WaxRow(icon: "globe", title: s.name,
               subtitle: "\(s.appCount) app\(s.appCount == 1 ? "" : "s")" + (s.updated.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? ""),
               subtitleLines: 2) {
            if model.loading.contains(s.id) { ProgressView() }
            else { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub) }
        }
    }

    private var emptyState: some View {
        WaxEmptyState(title: "No sources yet",
                      message: "Wax ships with none. Paste the address of a source file, or a link straight to an IPA. You are responsible for what you load.",
                      actionTitle: "Add a source") { addFocused = true }
    }
}

/// The apps in one source, searchable, each with a Get button.
struct SourceAppsView: View {
    let sourceID: UUID
    @EnvironmentObject private var model: SourcesModel
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var signing: SigningModel
    @EnvironmentObject private var router: Router
    @AppStorage("signAfterDownload") private var signAfterDownload = false
    @State private var query = ""
    @State private var selectedApp: SourceApp?

    private var source: SavedSource? { model.sources.first { $0.id == sourceID } }
    private var matches: [SourceApp] {
        let all = model.apps(of: sourceID)
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.bundleID.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                WaxHeader(title: source?.name ?? "Source", subtitle: "\(model.apps(of: sourceID).count) apps")
                if let m = model.message { WaxFeedbackCard(tone: .bad, text: m) }
                // Long sources (thousands of apps) show the first 300 matches; searching narrows them.
                ForEach(matches.prefix(300)) { app in appRow(app) }
                if matches.count > 300 {
                    Text("Showing 300 of \(matches.count). Search to narrow it down.").font(.footnote).foregroundStyle(Wax.sub).padding(.vertical, 8)
                }
                if matches.isEmpty { noApps }
            }
            .padding(.horizontal, Wax.inset)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
        .sheet(item: $selectedApp) { app in details(app) }
        .onChange(of: router.tab) { _, tab in if tab != .sources { selectedApp = nil } }
        .background(Wax.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Wax.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: model.message) { _, new in if let new { AccessibilityNotification.Announcement(new).post() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.refresh(sourceID) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.loading.contains(sourceID))
                    .accessibilityLabel("Refresh this source")
            }
        }
    }

    private var noApps: some View {
        if query.isEmpty {
            WaxEmptyState(symbol: "shippingbox", title: "This source lists no apps",
                          message: "Refresh to ask the source again.")
        } else {
            WaxEmptyState(symbol: "magnifyingglass", title: "No apps match",
                          message: "Nothing in this source matches “\(query)”.",
                          actionTitle: "Clear search") { query = "" }
        }
    }

    private func appRow(_ app: SourceApp) -> some View {
        let subtitle = [app.version.isEmpty ? nil : app.version,
                        app.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Button { selectedApp = app } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: app.iconURL) { image in image.resizable().scaledToFill() } placeholder: {
                        Image(systemName: "shippingbox").foregroundStyle(Wax.link)
                    }
                    .frame(width: 40, height: 40)
                    .background(Wax.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.callout.weight(.semibold)).foregroundStyle(Wax.text).lineLimit(2)
                        Text(subtitle)
                            .font(.footnote).foregroundStyle(Wax.sub).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity, minHeight: Wax.touch, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Details for " + app.name)
            .accessibilityValue(subtitle)
            .accessibilityHint("Shows source-reported information and any saved IPA metadata")
            getButton(app)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: Wax.rowHeight)
        .background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous).stroke(Wax.line, lineWidth: 1))
    }

    private func details(_ app: SourceApp) -> some View {
        let info = SourceAppDetails(app: app, saved: model.savedEntry(app, source: sourceID, library: library))
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source-reported information").font(.headline).foregroundStyle(Wax.text)
                    Text("These are claims from the source, not an identity, integrity or installation check. Downloaded IPAs are inspected before saving.")
                        .font(.footnote).foregroundStyle(Wax.sub)
                    fields(info.advertised)
                    if !info.saved.isEmpty {
                        Text("Previous committed download").font(.headline).foregroundStyle(Wax.text)
                        Text("This entry is associated with an actual successful shelf commit. It does not establish that a remote download link still serves those bytes.")
                            .font(.footnote).foregroundStyle(Wax.sub)
                        fields(info.saved)
                    }
                    ForEach(info.differences, id: \.self) { text in WaxFeedbackCard(tone: .bad, text: text) }
                    if let message = model.message { WaxFeedbackCard(tone: .bad, text: message) }
                    getButton(app).frame(maxWidth: .infinity, alignment: .center)
                }.padding(Wax.inset)
            }
            .background(Wax.bg.ignoresSafeArea())
            .navigationTitle("App details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedApp = nil } } }
        }
        .presentationDetents([.large])
    }
    private func fields(_ values: [SourceAppDetails.Field]) -> some View {
        WaxPanel {
            ForEach(values) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.title).font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                    Text(field.value).font(.footnote).foregroundStyle(Wax.sub).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                if field.id != values.last?.id { WaxDivider() }
            }
        }
    }

    @ViewBuilder private func getButton(_ app: SourceApp) -> some View {
        if model.isSaving(app, source: sourceID) {
            ProgressView().frame(width: Wax.touch, height: Wax.touch).accessibilityLabel("Saving \(app.name) to the IPA shelf")
        } else if let p = model.progress(app, source: sourceID) {
            ZStack {
                Circle().stroke(Wax.line, lineWidth: 3)
                Circle().trim(from: 0, to: max(0.03, p)).stroke(Wax.link, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            .frame(width: Wax.touch, height: Wax.touch)   // the row keeps its 44 pt target while the ring stays small
            .accessibilityLabel("Downloading \(app.name)").accessibilityValue("\(Int(p * 100)) percent")
        } else if model.isFiled(app, source: sourceID, library: library) {
            Button { model.get(app, from: sourceID, signAfter: signAfterDownload, library: library, signing: signing, router: router) } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Wax.ok).frame(width: Wax.touch, height: Wax.touch)
            }.buttonStyle(.plain)
                .accessibilityLabel("A previous download from this entry is on your IPA shelf")
                .accessibilityHint("Download again to check for changed contents")
        } else {
            Button {
                model.get(app, from: sourceID, signAfter: signAfterDownload, library: library, signing: signing, router: router)
            } label: {
                Text(model.retainedFile(app, source: sourceID) == nil ? "Get" : "Retry Save").font(.subheadline.weight(.bold)).foregroundStyle(Wax.onAccent)
                    .padding(.horizontal, 18).frame(minHeight: Wax.touch).background(Wax.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.retainedFile(app, source: sourceID) == nil ? "Get \(app.name)" : "Retry saving \(app.name)")
        }
    }
}
