import CredentialKit
import Foundation
import IPAKit
import SwiftUI

/// UI-facing wrapper around `CredentialStore`. Holds no secrets beyond the .p12 bytes and password
/// between picking the file and confirming the password; both are cleared as soon as the import ends.
@MainActor
final class CredentialsModel: ObservableObject {
    @Published private(set) var certificates: [CertificateInfo] = []
    @Published private(set) var profiles: [ProfileInfo] = []
    @Published var message: String?
    @Published var awaitingPassword = false
    /// Shown while a file is being fetched from iCloud or read; nil when idle.
    @Published var busyMessage: String?

    private(set) var store: CredentialStore?
    private var pendingP12: Data?
    private var pendingName = ""

    var pendingFileName: String { pendingName }

    init(store: CredentialStore? = nil) {
        if let store {
            self.store = store
        } else {
            do {
                let base = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                self.store = try CredentialStore(directory: base.appendingPathComponent("Credentials", isDirectory: true))
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "Credential storage is unavailable."
            }
        }
        reload()
    }

    private func reload() {
        certificates = store?.certificates() ?? []
        profiles = store?.profiles() ?? []
    }

    // MARK: Importing

    func picked(p12 result: Result<URL, Error>) {
        load(result) { [weak self] data, name in
            self?.pendingP12 = data
            self?.pendingName = name
            self?.awaitingPassword = true
        }
    }

    func confirmPassword(_ password: String) {
        defer { clearPending() }
        guard let data = pendingP12, let store else { return }
        do {
            let infos = try store.importCertificates(p12: data, password: password)
            message = infos.count == 1 ? "Imported \(infos[0].commonName)." : "Imported \(infos.count) identities: " + infos.map(\.commonName).joined(separator: ", ") + "."
            ImportLogs.shared.log("p12 import ok")
        } catch {
            message = describe(error)
            ImportLogs.shared.log("p12 import failed: \(describe(error))")
        }
        reload()
    }

    func cancelPassword() { clearPending() }

    func picked(profile result: Result<URL, Error>) {
        load(result) { [weak self] data, _ in
            guard let self, let store = self.store else { return }
            do {
                let info = try store.importProfile(data)
                self.message = "Imported profile \(info.name)."
                ImportLogs.shared.log("profile import ok")
            } catch {
                self.message = self.describe(error)
                ImportLogs.shared.log("profile import failed: \(self.describe(error))")
            }
            self.reload()
        }
    }

    // MARK: Deleting and checking

    func delete(certificate: CertificateInfo) {
        do { try store?.deleteCertificate(id: certificate.id) } catch { message = describe(error) }
        reload()
    }

    func delete(profile: ProfileInfo) {
        do { try store?.deleteProfile(id: profile.id) } catch { message = describe(error) }
        reload()
    }

    // MARK: Helpers

    /// Reads the picked file off the main thread (it may have to download from iCloud first), then hands the
    /// bytes to `then` on the main actor. Every failure ends in `message`; nothing is reported as success.
    private func load(_ result: Result<URL, Error>, then: @escaping @MainActor (Data, String) -> Void) {
        switch result {
        case .failure(let error):
            message = "The file could not be selected: \(error.localizedDescription)"
        case .success(let url):
            busyMessage = "Opening “\(url.lastPathComponent)”…"
            ImportLogs.shared.log("picked \(ImportLog.describe(url))")
            let model = self   // the model is main-actor isolated, so it is safe to hand to the background task
            let fileName = url.lastPathComponent
            Task.detached {
                defer { discardPickerCopy(url) }
                do {
                    let data = try ExternalFile.withReadAccess(to: url, progress: { text in
                        Task { @MainActor in model.busyMessage = text }
                    }) { readURL in
                        try Data(contentsOf: readURL)
                    }
                    ImportLogs.shared.log("read ok \(fileName) \(data.count) bytes")
                    await MainActor.run {
                        model.busyMessage = nil
                        then(data, fileName)
                    }
                } catch {
                    ImportLogs.shared.log("read failed \(fileName): \(ImportLog.describe(error))")
                    await MainActor.run {
                        model.busyMessage = nil
                        model.message = (error as? LocalizedError)?.errorDescription
                            ?? "“\(fileName)” could not be read: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func clearPending() {
        pendingP12 = nil
        pendingName = ""
        awaitingPassword = false
    }

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Import failed."
    }
}
