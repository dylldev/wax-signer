import SwiftUI

struct CredentialImportSheet: View {
    @EnvironmentObject private var model: CredentialsModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var nickname = ""
    @State private var choosingCertificate = true
    @State private var showPicker = false
    private enum Field: Hashable { case password, nickname }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    fileField(".P12 Certificate", name: model.pendingFileName, certificate: true)
                    fileField("Mobile Provision", name: model.pendingProfileName, certificate: false)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Certificate Password").font(.subheadline.weight(.semibold))
                        SecureField("", text: $password)
                            .focused($focusedField, equals: .password)
                            .accessibilityLabel("Certificate Password")
                            .textContentType(.password)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: Wax.touch)
                            .background(Wax.card, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .password }
                        Text("Used only for this import. Wax does not save your password.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Nickname").font(.subheadline.weight(.semibold))
                        TextField("Optional", text: $nickname)
                            .focused($focusedField, equals: .nickname)
                            .accessibilityLabel("Custom Nickname")
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(minHeight: Wax.touch)
                            .background(Wax.card, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = .nickname }
                    }
                    if let busy = model.busyMessage {
                        ProgressView(busy).frame(maxWidth: .infinity)
                    }
                    if let message = model.message {
                        Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("credential-import-message")
                    }
                    Button("Done") {
                        focusedField = nil
                        let temporaryPassword = password; password = ""
                        model.confirmImport(password: temporaryPassword, nickname: nickname)
                    }
                    .buttonStyle(WaxPrimaryButtonStyle())
                    .disabled(!model.canSubmitImport)
                }
                .foregroundStyle(Wax.text)
                .padding(Wax.inset)
                .disabled(model.isCommittingImport)
            }
            .background(Wax.bg.ignoresSafeArea())
            .tint(Wax.link)
            .toolbarBackground(Wax.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Import credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        focusedField = nil
                        password = ""; nickname = ""; model.dismissImport(); model.message = nil; dismiss()
                    } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close credential import")
                    .disabled(model.isCommittingImport)
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { picked in
                    showPicker = false
                    guard let picked else { return }
                    if choosingCertificate { model.stageCertificate(.success(picked)) }
                    else { model.stageProfile(.success(picked)) }
                }
            }
        }
        .interactiveDismissDisabled(model.isCommittingImport)
        .onChange(of: model.importCompleted) { _, complete in
            if complete { password = ""; nickname = ""; model.message = nil; dismiss() }
        }
    }

    private func fileField(_ title: String, name: String, certificate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Button {
                choosingCertificate = certificate; showPicker = true
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(name.isEmpty ? "Choose file" : name)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "folder")
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Wax.card, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Choose " + title)
            .accessibilityValue(name.isEmpty ? "No file selected" : name)
            .disabled(model.busyMessage != nil)
        }
    }
}
