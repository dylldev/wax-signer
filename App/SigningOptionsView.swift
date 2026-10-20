import CoreTransferable
import UniformTypeIdentifiers
import CredentialKit
import PhotosUI
import SigningKit
import SwiftUI

/// Extra changes to make to an app before signing it, with the option to keep the switches as defaults.
struct SigningOptionsView: View {
    @ObservedObject var model: SigningModel
    @EnvironmentObject private var credentials: CredentialsModel
    @State private var saved = false
    @State private var pickedIcon: PhotosPickerItem?
    @State private var iconTask: Task<Void, Never>?
    @State private var iconGeneration = UUID()
    @State private var readingIcon = false
    @State private var pickingEntitlements = false
    @State private var pickingLibrary = false
    @State private var fileProblem: String?
    @State private var baseline: AppEdits?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                WaxSectionLabel(text: "This app")
                WaxPanel {
                    field("Name", text: binding(\.displayName), placeholder: model.ipaInfo?.displayName ?? "Keep the app's name")
                    WaxDivider()
                    field("Version", text: binding(\.version), placeholder: model.ipaInfo?.version ?? "Keep")
                    WaxDivider()
                    field("Build", text: binding(\.build), placeholder: model.ipaInfo?.build ?? "Keep")
                    WaxDivider()
                    field("Bundle ID", text: binding(\.bundleIdentifier), placeholder: model.ipaInfo?.bundleIdentifier ?? "Keep", mono: true)
                    WaxDivider()
                    field("Minimum iOS", text: binding(\.minimumOSVersion), placeholder: model.ipaInfo?.minimumOSVersion ?? "Keep")
                }
                note("These apply to this app only and are not saved as defaults. A custom bundle ID replaces the app's own one, so it only makes sense with a profile that allows it.")

                WaxSectionLabel(text: "More for this app")
                WaxPanel {
                    iconRow
                    WaxDivider()
                    profileRow
                    WaxDivider()
                    entitlementsRow
                }
                if let fileProblem { note(fileProblem).foregroundStyle(Wax.bad) }

                WaxSectionLabel(text: "Libraries")
                libraryPanel
                note("Adds .dylib files, or the .dylib files inside a .deb, to this app. They load when the app starts. Only apps that are not App Store encrypted, and only if the app's header has room.")

                WaxSectionLabel(text: "Changes to every app")
                WaxPanel {
                    toggle("Randomize bundle ID", "Adds a random string to every bundle ID.", \.randomizeBundleID)
                    WaxDivider()
                    toggle("Remove URL schemes", "Stops the app from opening links of its own.", \.removeURLSchemes)
                    WaxDivider()
                    toggle("Remove app extensions", "Deletes widgets and other extensions, which free accounts often cannot sign.", \.removeExtensions)
                    WaxDivider()
                    toggle("Remove Watch app", "Deletes the bundled Apple Watch app.", \.removeWatchApp)
                    WaxDivider()
                    toggle("File sharing", "Shows the app's files in the Files app.", \.enableFileSharing)
                    WaxDivider()
                    toggle("High frame rate", "Lets the app run at the screen's full refresh rate.", \.enableProMotion)
                    WaxDivider()
                    toggle("Game mode", "Tells iOS this is a game, for the game overlay and steady performance.", \.gameMode)
                    WaxDivider()
                    toggle("iPad full screen", "Stops the app from running in a window on iPad.", \.iPadFullScreen)
                    WaxDivider()
                    toggle("Remove device limits", "Lets an app made for another device, or only for iPad, run on this iPhone.", \.removeDeviceRestriction)
                    WaxDivider()
                    appearancePicker
                }

                WaxSectionLabel(text: "Advanced: app settings file (Info.plist)")
                plistEditor
                note("Each app carries a settings file. Add a key to set it, or choose Delete to remove one. This is for people who know the key they want; the bundle ID has its own option above.")

                VStack(spacing: 4) {
                    Button("Reset to defaults") { cancelIconRead(); model.resetEditsToDefaults(); saved = false }.buttonStyle(WaxSecondaryButtonStyle())
                }
                .padding(.top, 8)
                note("Defaults are used for every app you sign. Switches you change here apply to the next signing even if you do not save them.")
            }
            .padding(.horizontal, Wax.inset)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Wax.bg.ignoresSafeArea())
        .navigationTitle("Signing options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Wax.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { model.saveEditsAsDefaults(); saved = true; baseline = model.edits } label: {
                Label(saved ? "Saved" : "Save as defaults", systemImage: saved ? "checkmark" : "tray.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WaxPrimaryButtonStyle())
            .disabled(!hasChanges || saved)
            .padding(.horizontal, Wax.inset).padding(.vertical, 8)
            .background(Wax.bg.opacity(0.96))
        }
        .onAppear { baseline = model.edits }
        .onDisappear { cancelIconRead() }
        .onChange(of: model.edits) { _, _ in saved = false }
    }

    // MARK: pieces

    private var hasChanges: Bool { baseline.map { $0 != model.edits } ?? false }

    private func binding(_ key: WritableKeyPath<AppEdits, String?>) -> Binding<String> {
        Binding(get: { model.edits[keyPath: key] ?? "" }, set: { model.edits[keyPath: key] = $0.isEmpty ? nil : $0 })
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, mono: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.subheadline).foregroundStyle(Wax.sub).frame(width: 96, alignment: .leading)
            TextField(placeholder, text: text)
                .accessibilityLabel(title)
                .font(mono ? .footnote.monospaced() : .subheadline)
                .foregroundStyle(Wax.text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .frame(minHeight: 48)
    }

    private func toggle(_ title: String, _ detail: String, _ key: WritableKeyPath<AppEdits, Bool>) -> some View {
        Toggle(isOn: Binding(get: { model.edits[keyPath: key] }, set: { model.edits[keyPath: key] = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                Text(detail).font(.footnote).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Wax.link)
        .padding(.vertical, 10)
    }

    private func cancelIconRead() {
        iconGeneration = UUID(); iconTask?.cancel(); iconTask = nil; readingIcon = false; pickedIcon = nil
    }

    private var iconRow: some View {
        VStack(spacing: 8) {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Icon").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                Text(model.edits.iconPNG == nil ? "The app's own icon." : "A new icon will be used.").font(.footnote).foregroundStyle(Wax.sub)
            }
            Spacer()
            if model.edits.iconPNG != nil { Button("Reset") { cancelIconRead(); model.edits.iconPNG = nil }.font(.subheadline).foregroundStyle(Wax.sub) }
            PhotosPicker(selection: $pickedIcon, matching: .images) {
                Text("Choose").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
            }
        }
        if readingIcon { ProgressView("Reading icon…").font(.footnote) }
        if let data = model.edits.iconPNG, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Chosen app icon")
        }
        }
        .frame(minHeight: 56)
        .onChange(of: pickedIcon) { _, item in
            guard let item else { return }
            iconTask?.cancel()
            let generation = UUID(); iconGeneration = generation; readingIcon = true
            iconTask = Task {
                do {
                    guard let icon = try await item.loadTransferable(type: PreparedIcon.self) else { throw BoundedIcon.Failure.unreadable }
                    guard !Task.isCancelled, iconGeneration == generation else { return }
                    model.edits.iconPNG = icon.data; fileProblem = nil
                } catch {
                    guard !Task.isCancelled, iconGeneration == generation else { return }
                    fileProblem = (error as? LocalizedError)?.errorDescription ?? "The icon could not be loaded. Choose another image."
                }
                if iconGeneration == generation { readingIcon = false; pickedIcon = nil; iconTask = nil }
            }
        }
    }

    private var profileRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                Text("Which provisioning profile signs this app.").font(.footnote).foregroundStyle(Wax.sub)
            }
            Spacer()
            Picker("Profile", selection: $model.profileChoice) {
                Text("Automatic").tag(UUID?.none)
                ForEach(credentials.profiles) { p in Text(p.name).tag(UUID?.some(p.id)) }
            }
            .labelsHidden().tint(Wax.link)
        }
        .frame(minHeight: 56)
    }

    private var entitlementsRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Entitlements").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                Text(model.customEntitlementsName ?? "The app's own. Only what the profile allows is kept.")
                    .font(.footnote).foregroundStyle(Wax.sub).lineLimit(2)
            }
            Spacer()
            if model.customEntitlementsName != nil {
                Button("Reset") { try? model.setEntitlements(from: nil) }.font(.subheadline).foregroundStyle(Wax.sub)
            }
            Button("Choose") { pickingEntitlements = true }.font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
        }
        .frame(minHeight: 56)
        .sheet(isPresented: $pickingEntitlements) {
            DocumentPicker { url in
                pickingEntitlements = false
                guard let url else { return }
                do { try model.setEntitlements(from: url); fileProblem = nil }
                catch { fileProblem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
            }
        }
    }

    private var libraryPanel: some View {
        WaxPanel {
            ForEach(Array(model.edits.injectLibraries.enumerated()), id: \.offset) { index, url in
                HStack {
                    Image(systemName: url.pathExtension.lowercased() == "deb" ? "shippingbox" : "puzzlepiece.extension")
                        .foregroundStyle(Wax.link).frame(width: 24)
                    Text(url.lastPathComponent).font(.subheadline).foregroundStyle(Wax.text).lineLimit(1)
                    Spacer()
                    Button { removeLibrary(at: index) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Wax.sub) }
                        .accessibilityLabel("Remove \(url.lastPathComponent)")
                }
                .frame(minHeight: 48)
                WaxDivider()
            }
            Button { pickingLibrary = true } label: {
                Label("Add a .dylib, .framework or .deb", systemImage: "plus").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }
        .sheet(isPresented: $pickingLibrary) {
            DocumentPicker { url in
                pickingLibrary = false
                guard let url else { return }
                keepLibrary(url)
            }
        }
    }

    /// Moves the picked file out of the picker's temporary copy, which iOS removes soon after, into a folder that lasts until signing.
    private func keepLibrary(_ picked: URL) {
        defer { discardPickerCopy(picked) }
        let ext = picked.pathExtension.lowercased()
        guard ["dylib", "framework", "deb"].contains(ext) else { fileProblem = "Choose a .dylib, a .framework or a .deb file."; return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Libraries/\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let kept = dir.appendingPathComponent(picked.lastPathComponent)
            try FileManager.default.copyItem(at: picked, to: kept)
            model.edits.injectLibraries.append(kept)
            fileProblem = nil
        } catch { fileProblem = "That file could not be read: \(error.localizedDescription)" }
    }

    private func removeLibrary(at index: Int) {
        let url = model.edits.injectLibraries.remove(at: index)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
            Picker("Appearance", selection: Binding(get: { model.edits.appearance }, set: { model.edits.appearance = $0 })) {
                Text("Keep").tag(AppEdits.Appearance?.none)
                Text("Phone").tag(AppEdits.Appearance?.some(.system))
                Text("Light").tag(AppEdits.Appearance?.some(.light))
                Text("Dark").tag(AppEdits.Appearance?.some(.dark))
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 10)
    }

    private var plistEditor: some View {
        WaxPanel {
            ForEach($model.edits.plistEdits) { $edit in
                PlistEditRow(edit: $edit) { model.edits.plistEdits.removeAll { $0.id == edit.id } }
                WaxDivider()
            }
            Button {
                model.edits.plistEdits.append(PlistEdit(key: "", value: .string("")))
            } label: {
                Label("Add a key", systemImage: "plus").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(Wax.sub)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}


/// One Info.plist change: a key, what kind of value, and the value (or Delete).
private struct PlistEditRow: View {
    @Binding var edit: PlistEdit
    let remove: () -> Void

    private enum Kind: String, CaseIterable { case text = "Text", flag = "Switch", number = "Number", delete = "Delete" }
    private var kind: Kind {
        switch edit.value { case .string?: .text; case .bool?: .flag; case .number?: .number; case nil: .delete }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Key, for example UIFileSharingEnabled", text: $edit.key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.footnote.monospaced()).foregroundStyle(Wax.text)
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.foregroundStyle(Wax.bad)
            }
            HStack {
                Picker("Kind", selection: Binding(get: { kind }, set: setKind)) {
                    ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            switch edit.value {
            case .string(let s)?:
                TextField("Value", text: Binding(get: { s }, set: { edit.value = .string($0) })).font(.subheadline).foregroundStyle(Wax.text)
            case .bool(let b)?:
                Toggle("Value", isOn: Binding(get: { b }, set: { edit.value = .bool($0) })).tint(Wax.link)
            case .number(let n)?:
                TextField("Value", text: Binding(get: { String(n) }, set: { edit.value = .number(Double($0) ?? n) }))
                    .keyboardType(.numbersAndPunctuation).font(.subheadline).foregroundStyle(Wax.text)
            case nil:
                Text("This key is removed from the app.").font(.footnote).foregroundStyle(Wax.sub)
            }
        }
        .padding(.vertical, 10)
    }

    private func setKind(_ k: Kind) {
        switch k {
        case .text: edit.value = .string("")
        case .flag: edit.value = .bool(true)
        case .number: edit.value = .number(0)
        case .delete: edit.value = nil
        }
    }
}

/// FileRepresentation avoids loading the entire Photos item into Data before applying a byte budget.
private struct PreparedIcon: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let file = received.file
            let worker = Task.detached { try BoundedIcon.prepare(file: file) }
            let data = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            return PreparedIcon(data: data)
        }
    }
}
