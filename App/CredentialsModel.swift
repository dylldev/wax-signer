import CredentialKit
import Foundation
import InstallKit
import IPAKit
import SwiftUI

/// Pending encrypted input stays in memory for retry; passwords exist only in the confirmed worker invocation.
@MainActor
final class CredentialsModel: ObservableObject {
    @Published private(set) var certificates: [CertificateInfo] = []
    @Published private(set) var profiles: [ProfileInfo] = []
    @Published private(set) var identityChecks: [UUID: String] = [:]
    private var checkedCertificates: [CertificateInfo] = []
    private var identityCheckToken = UUID()
    @Published var message: String?
    @Published var awaitingPassword = false
    @Published private(set) var busyMessage: String?
    @Published private(set) var importedItemID: String?
    private(set) var store: CredentialStore?
    private var pendingP12: Data?
    @Published private var pendingName = ""
    private var pendingProfile: Data?
    @Published private(set) var pendingProfileName = ""
    @Published private(set) var importCompleted = false
    private let preferences: UserDefaults
    private let nicknameKey = "credential.displayNicknames"
    var canSubmitImport: Bool { busyMessage == nil && (pendingP12 != nil || pendingProfile != nil) }
    var isCommittingImport: Bool { importing }
    private var token = UUID()
    private var operation: Task<Void, Never>?
    private var importing = false
    private var readToken: UUID?
    private let certificateImport: @Sendable (CredentialStore, Data, String) throws -> [CertificateInfo]
    private let profileImport: @Sendable (CredentialStore, Data) throws -> ProfileInfo
    var pendingFileName: String { pendingName }
    var canCancelReading: Bool { readToken != nil && !importing }
    var canRetryPassword: Bool { pendingP12 != nil && !awaitingPassword && busyMessage == nil }

    init(store: CredentialStore? = nil, preferences: UserDefaults = .standard,
         certificateImport: @escaping @Sendable (CredentialStore, Data, String) throws -> [CertificateInfo] = { try $0.importCertificates(p12: $1, password: $2) },
         profileImport: @escaping @Sendable (CredentialStore, Data) throws -> ProfileInfo = { try $0.importProfile($1) }) {
        self.preferences = preferences
        self.certificateImport = certificateImport; self.profileImport = profileImport
        if let store { self.store = store }
        else {
            do {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                self.store = try CredentialStore(directory: base.appendingPathComponent("Credentials", isDirectory: true))
            } catch { message = "Credential storage is unavailable. " + Self.describe(error) }
        }
        certificates = self.store?.certificates() ?? []; profiles = self.store?.profiles() ?? []
    }

    func displayName(for certificate: CertificateInfo) -> String {
        let nickname = preferences.dictionary(forKey: nicknameKey)?[certificate.id.uuidString] as? String
        if let nickname, !nickname.isEmpty { return nickname }
        return certificate.organization ?? certificate.commonName
    }

    @discardableResult func stageCertificate(_ result: Result<URL, Error>) -> Task<Void, Never>? {
        guard !importing else { return nil }
        pendingP12 = nil; pendingName = ""; importCompleted = false
        return load(result, limit: 5 * 1024 * 1024, clearDraft: false) { data, name, _ in
            self.pendingP12 = data; self.pendingName = name
        }
    }

    @discardableResult func stageProfile(_ result: Result<URL, Error>) -> Task<Void, Never>? {
        guard !importing else { return nil }
        pendingProfile = nil; pendingProfileName = ""; importCompleted = false
        return load(result, limit: 1024 * 1024, clearDraft: false) { data, name, _ in
            self.pendingProfile = data; self.pendingProfileName = name
        }
    }

    func dismissImport() { cancelPassword() }

    @discardableResult func confirmImport(password: String, nickname: String) -> Task<Void, Never>? {
        guard canSubmitImport else { return nil }
        return commitImport(password: password, nickname: nickname, profile: pendingProfile)
    }

    func identityStatus(for certificate: CertificateInfo) -> IdentityStatus {
        let check = checkedCertificates == certificates ? identityChecks[certificate.id] : nil
        return IdentityReadiness.status(for: certificate, profiles: profiles, identityCheck: check)
    }

    /// Refresh display evidence off the UI thread. Signing resolves the identity again when preparing.
    func refreshIdentityChecks() async {
        let generation = UUID(); identityCheckToken = generation
        identityChecks = [:]; checkedCertificates = []
        let snapshot = certificates
        guard let store else { return }
        let results = await Task.detached { () -> [UUID: String] in
            var results: [UUID: String] = [:]
            for certificate in snapshot {
                do { _ = try store.identity(for: certificate.id); results[certificate.id] = "" }
                catch CredentialError.notFound {
                    results[certificate.id] = "The signing certificate is unavailable. Unlock this iPhone and reopen Wax. "
                        + "If it stays unavailable, keep your original .p12 file and password before importing it again."
                } catch {
                    results[certificate.id] = (error as? CredentialError)?.errorDescription
                        ?? "The signing certificate could not be checked. Reopen Wax and try again."
                }
            }
            return results
        }.value
        guard !Task.isCancelled, identityCheckToken == generation, certificates == snapshot else { return }
        checkedCertificates = snapshot; identityChecks = results
    }

    @discardableResult func picked(p12 result: Result<URL, Error>) -> Task<Void, Never>? {
        load(result, limit: 5 * 1024 * 1024) { data, name, _ in
            self.pendingP12 = data; self.pendingName = name; self.awaitingPassword = true
        }
    }
    func requestPasswordRetry() {
        guard canRetryPassword else { return }
        message = nil; awaitingPassword = true
    }
    @discardableResult func confirmPassword(_ password: String) -> Task<Void, Never>? {
        guard pendingP12 != nil else { return nil }
        return commitImport(password: password, nickname: "", profile: nil)
    }

    private func commitImport(password: String, nickname: String, profile: Data?) -> Task<Void, Never>? {
        guard !importing, busyMessage == nil, pendingP12 != nil || profile != nil else { return nil }
        guard let store else { message = "Credential storage is unavailable. Free space and restart Wax before retrying."; return nil }
        let data = pendingP12
        let id = UUID(); token = id; importing = true; awaitingPassword = false; message = nil; importCompleted = false
        busyMessage = "Importing credentials…"; importedItemID = nil
        let importer = certificateImport, provisionImporter = profileImport
        let work = Task {
            defer { if token == id { importing = false; busyMessage = nil } }
            var imported: [CertificateInfo] = []
            var targetID: String?
            var outcomeMessage: String?
            var completed = false
            do {
                if let data {
                    imported = try await Task.detached {
                        let infos = try importer(store, data, password)
                        guard !infos.isEmpty else { throw CredentialError.storage("no identity was imported") }
                        return infos
                    }.value
                    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        var names = preferences.dictionary(forKey: nicknameKey) ?? [:]
                        for info in imported { names[info.id.uuidString] = trimmed }
                        preferences.set(names, forKey: nicknameKey)
                    }
                    targetID = imported.first.map { "credential-\($0.id)" }
                }
                var provision: ProfileInfo?
                if let profile {
                    provision = try await Task.detached { try provisionImporter(store, profile) }.value
                }
                guard token == id else { return }
                clearPending()
                if let provision {
                    targetID = targetID ?? "credential-\(provision.id)"
                    outcomeMessage = imported.isEmpty ? "Imported profile \(provision.name)." : "Imported certificate and profile \(provision.name)."
                } else {
                    outcomeMessage = imported.count == 1 ? "Imported \(imported[0].commonName)." : "Imported \(imported.count) identities: " + imported.map(\.commonName).joined(separator: ", ") + "."
                }
                completed = true
                ImportLogs.shared.log("credential import ok")
            } catch {
                guard token == id else { return }
                if !imported.isEmpty {
                    clearPending()
                    outcomeMessage = "Certificate imported: " + imported.map(\.commonName).joined(separator: ", ")
                        + ". Profile was not imported. " + Self.describe(error)
                } else {
                    // Keep bounded encrypted input for an explicit retry, never the password.
                    outcomeMessage = Self.describe(error)
                }
                ImportLogs.shared.log("credential import failed")
            }
            let snapshot = await Task.detached { (store.certificates(), store.profiles()) }.value
            guard token == id else { return }
            certificates = snapshot.0; profiles = snapshot.1
            importedItemID = targetID
            message = outcomeMessage
            importCompleted = completed
        }
        operation = work; return work
    }
    /// Confirmation begins a non-cancellable Keychain commit. Do not pretend to roll it back on dismissal.
    func cancelPassword() {
        guard !importing else { return }
        operation?.cancel(); token = UUID(); readToken = nil; busyMessage = nil; clearPending()
    }
    func dismissPassword() { if !importing { cancelPassword() } }

    @discardableResult func picked(profile result: Result<URL, Error>) -> Task<Void, Never>? {
        load(result, limit: 1024 * 1024) { data, _, id in
            guard let store = self.store else { self.message = "Credential storage is unavailable."; return }
            self.importing = true; self.busyMessage = "Importing profile…"
            defer { if self.token == id { self.importing = false; self.busyMessage = nil } }
            let importer = self.profileImport
            do {
                let result = try await Task.detached {
                    let info = try importer(store, data)
                    return (info, store.certificates(), store.profiles())
                }.value
                guard self.token == id else { return }
                self.certificates = result.1; self.profiles = result.2
                self.importedItemID = "credential-\(result.0.id)"; self.message = "Imported profile \(result.0.name)."
                ImportLogs.shared.log("profile import ok")
            } catch { if self.token == id { self.message = Self.describe(error); ImportLogs.shared.log("profile import failed") } }
        }
    }
    func delete(certificate: CertificateInfo) { remove(nicknameID: certificate.id) { try $0.deleteCertificate(id: certificate.id) } }
    func delete(profile: ProfileInfo) { remove { try $0.deleteProfile(id: profile.id) } }
    private func remove(nicknameID: UUID? = nil, _ action: @escaping @Sendable (CredentialStore) throws -> Void) {
        guard busyMessage == nil, let store else { return }
        busyMessage = "Removing credential…"; importing = true
        operation = Task {
            defer { busyMessage = nil; importing = false }
            do {
                let snapshot = try await Task.detached { try action(store); return (store.certificates(), store.profiles()) }.value
                certificates = snapshot.0; profiles = snapshot.1
                if let nicknameID {
                    var names = preferences.dictionary(forKey: nicknameKey) ?? [:]
                    names.removeValue(forKey: nicknameID.uuidString)
                    preferences.set(names, forKey: nicknameKey)
                }
            } catch { message = Self.describe(error) }
        }
    }

    private func load(_ result: Result<URL, Error>, limit: Int, clearDraft: Bool = true,
                      then: @escaping @MainActor (Data, String, UUID) async -> Void) -> Task<Void, Never>? {
        guard !importing else { message = "Wait for the confirmed credential import to finish."; return nil }
        operation?.cancel(); if clearDraft { clearPending() }; let id = UUID(); token = id; readToken = nil; message = nil; importedItemID = nil
        switch result {
        case .failure:
            busyMessage = nil; message = "The file could not be selected. Choose it again from Files."; return nil
        case .success(let url):
            readToken = id; busyMessage = "Opening “\(url.lastPathComponent)”…"
            let work = Task {
                do {
                    let data = try await Task.detached {
                        defer { discardPickerCopy(url) }
                        return try ExternalFile.withReadAccess(to: url, progress: { text in
                            Task { @MainActor in if self.readToken == id { self.busyMessage = text } }
                        }) { file in try Self.readBounded(file, limit: limit) }
                    }.value
                    guard token == id, !Task.isCancelled else { return }
                    readToken = nil; busyMessage = nil; await then(data, url.lastPathComponent, id)
                } catch {
                    guard token == id else { return }
                    readToken = nil; busyMessage = nil; message = Self.describe(error)
                    ImportLogs.shared.log("credential read failed")
                }
            }
            operation = work; return work
        }
    }
    nonisolated static func readBounded(_ file: URL, limit: Int) throws -> Data {
        guard limit > 0 else { throw CredentialError.fileTooLarge }
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              let size = attrs[.size] as? NSNumber, size.int64Value >= 0, size.int64Value <= Int64(limit) else { throw CredentialError.fileTooLarge }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            guard chunk.count <= limit - data.count else { throw CredentialError.fileTooLarge }
            data.append(chunk)
        }
        guard data.count == size.intValue else { throw CredentialError.storage("the input changed while reading; choose it again") }
        try handle.close(); return data
    }
    private func clearPending() { pendingP12 = nil; pendingName = ""; pendingProfile = nil; pendingProfileName = ""; awaitingPassword = false }
    nonisolated private static func describe(_ error: Error) -> String {
        // Known credential messages contain no password/key bytes. Unknown errors are not dumped to logs/UI.
        (error as? CredentialError)?.errorDescription ?? "Import failed. Check the file and free space, then retry."
    }
}
