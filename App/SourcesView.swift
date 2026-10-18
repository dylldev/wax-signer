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

    var body: some View {
        NavigationStack(path: $router.sourcesPath) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        WaxHeader(title: "Sources", subtitle: "Apps from places you add.").id("top")
                        addCard
                        if let m = model.message { messageCard(m) }
                        if model.sources.isEmpty { emptyState } else {
                            ForEach(model.sources) { source in
                                NavigationLink(value: source.id) { row(source) }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in actionSource = source })
                            }
                        }
                    }
                    .padding(.horizontal, Wax.inset)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Wax.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: router.reselectTick[.sources]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
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

    private var addCard: some View {
        WaxPanel {
            HStack(spacing: 10) {
                TextField("Paste a source or IPA address", text: $draft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .font(.subheadline).foregroundStyle(Wax.text)
                    .submitLabel(.go).onSubmit(add)
                Button("Add", action: add)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(draft.isEmpty ? Wax.sub : Wax.link)
                    .disabled(draft.isEmpty)
            }
            .frame(minHeight: 56)
        }
    }

    private func add() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        model.add(draft, signAfter: signAfterDownload, library: library, signing: signing, router: router)
        if URL(string: draft.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme == "https" { draft = "" }
    }

    private func row(_ s: SavedSource) -> some View {
        WaxRow(icon: "globe", title: s.name,
               subtitle: "\(s.appCount) app\(s.appCount == 1 ? "" : "s")" + (s.updated.map { " · " + $0.formatted(.relative(presentation: .named)) } ?? "")) {
            if model.loading.contains(s.id) { ProgressView() }
            else { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            WaxSeal(size: 56).opacity(0.5)
            Text("No sources yet").font(.callout.weight(.semibold)).foregroundStyle(Wax.text)
            Text("Wax comes with none. Paste the address of a source file, or a link straight to an IPA. You are responsible for what you load.")
                .font(.footnote).foregroundStyle(Wax.sub).multilineTextAlignment(.center).padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    private func messageCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Wax.bad).frame(width: 22, height: 22)
            Text(text).font(.footnote).foregroundStyle(Wax.text).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Wax.badBg, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .accessibilityElement(children: .combine)
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
                if let m = model.message {
                    Text(m).font(.footnote).foregroundStyle(Wax.bad).frame(maxWidth: .infinity, alignment: .leading)
                }
                // Long sources (thousands of apps) show the first 300 matches; searching narrows them.
                ForEach(matches.prefix(300)) { app in appRow(app) }
                if matches.count > 300 {
                    Text("Showing 300 of \(matches.count). Search to narrow it down.").font(.footnote).foregroundStyle(Wax.sub).padding(.vertical, 8)
                }
                if matches.isEmpty {
                    Text(query.isEmpty ? "This source lists no downloadable apps." : "No apps match “\(query)”.")
                        .font(.footnote).foregroundStyle(Wax.sub).padding(.top, 24)
                }
            }
            .padding(.horizontal, Wax.inset)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search apps")
        .background(Wax.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Wax.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.refresh(sourceID) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.loading.contains(sourceID))
            }
        }
    }

    private func appRow(_ app: SourceApp) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.iconURL) { image in image.resizable().scaledToFill() } placeholder: {
                Image(systemName: "shippingbox").foregroundStyle(Wax.link)
            }
            .frame(width: 40, height: 40)
            .background(Wax.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.callout.weight(.semibold)).foregroundStyle(Wax.text).lineLimit(1)
                Text([app.version.isEmpty ? nil : app.version, app.size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Wax.sub).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            getButton(app)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: Wax.rowHeight)
        .background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous).stroke(Wax.line, lineWidth: 1))
    }

    @ViewBuilder private func getButton(_ app: SourceApp) -> some View {
        if let p = model.downloads[app.id] {
            ZStack {
                Circle().stroke(Wax.line, lineWidth: 3)
                Circle().trim(from: 0, to: max(0.03, p)).stroke(Wax.link, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)
            .accessibilityLabel("Downloading").accessibilityValue("\(Int(p * 100)) percent")
        } else if model.filed.contains(app.id) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Wax.ok).frame(width: 44, height: 44)
                .accessibilityLabel("On your IPA shelf")
        } else {
            Button {
                model.get(app, from: sourceID, signAfter: signAfterDownload, library: library, signing: signing, router: router)
            } label: {
                Text("Get").font(.subheadline.weight(.bold)).foregroundStyle(Wax.onAccent)
                    .padding(.horizontal, 16).frame(height: 32).background(Wax.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
