import CredentialKit
import Foundation
import IPAKit
import SwiftUI

/// Pending encrypted input stays in memory for retry; passwords exist only in the confirmed worker invocation.
@MainActor
final class CredentialsModel: ObservableObject {
    @Published private(set) var certificates: [CertificateInfo] = []
    @Published private(set) var profiles: [ProfileInfo] = []
    @Published var message: String?
    @Published var awaitingPassword = false
    @Published private(set) var busyMessage: String?
    @Published private(set) var importedItemID: String?
    private(set) var store: CredentialStore?
    private var pendingP12: Data?
    private var pendingName = ""
    private var token = UUID()
    private var operation: Task<Void, Never>?
    private var importing = false
    private var readToken: UUID?
    private let certificateImport: @Sendable (CredentialStore, Data, String) throws -> [CertificateInfo]
    private let profileImport: @Sendable (CredentialStore, Data) throws -> ProfileInfo
    var pendingFileName: String { pendingName }
    var canCancelReading: Bool { readToken != nil && !importing }
    var canRetryPassword: Bool { pendingP12 != nil && !awaitingPassword && busyMessage == nil }

    init(store: CredentialStore? = nil,
         certificateImport: @escaping @Sendable (CredentialStore, Data, String) throws -> [CertificateInfo] = { try $0.importCertificates(p12: $1, password: $2) },
         profileImport: @escaping @Sendable (CredentialStore, Data) throws -> ProfileInfo = { try $0.importProfile($1) }) {
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
        guard !importing, busyMessage == nil, let data = pendingP12 else { return nil }
        guard let store else { message = "Credential storage is unavailable. Free space and restart Wax before retrying."; return nil }
        let id = UUID(); token = id; importing = true; awaitingPassword = false; message = nil
        busyMessage = "Importing credentials…"; importedItemID = nil
        let importer = certificateImport
        let work = Task {
            defer { if token == id { importing = false; busyMessage = nil } }
            do {
                let result = try await Task.detached {
                    let infos = try importer(store, data, password)
                    guard !infos.isEmpty else { throw CredentialError.storage("no identity was imported") }
                    return (infos, store.certificates(), store.profiles())
                }.value
                guard token == id else { return }
                clearPending(); certificates = result.1; profiles = result.2
                importedItemID = result.0.first.map { "credential-\($0.id)" }
                message = result.0.count == 1 ? "Imported \(result.0[0].commonName)." : "Imported \(result.0.count) identities: " + result.0.map(\.commonName).joined(separator: ", ") + "."
                ImportLogs.shared.log("p12 import ok")
            } catch {
                guard token == id else { return }
                // No password persisted. Keep only the bounded encrypted bytes for an explicit retry.
                message = Self.describe(error)
                ImportLogs.shared.log("p12 import failed")
            }
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
    func delete(certificate: CertificateInfo) { remove { try $0.deleteCertificate(id: certificate.id) } }
    func delete(profile: ProfileInfo) { remove { try $0.deleteProfile(id: profile.id) } }
    private func remove(_ action: @escaping @Sendable (CredentialStore) throws -> Void) {
        guard busyMessage == nil, let store else { return }
        busyMessage = "Removing credential…"; importing = true
        operation = Task {
            defer { busyMessage = nil; importing = false }
            do {
                let snapshot = try await Task.detached { try action(store); return (store.certificates(), store.profiles()) }.value
                certificates = snapshot.0; profiles = snapshot.1
            } catch { message = Self.describe(error) }
        }
    }

    private func load(_ result: Result<URL, Error>, limit: Int,
                      then: @escaping @MainActor (Data, String, UUID) async -> Void) -> Task<Void, Never>? {
        guard !importing else { message = "Wait for the confirmed credential import to finish."; return nil }
        operation?.cancel(); clearPending(); let id = UUID(); token = id; readToken = nil; message = nil; importedItemID = nil
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
    private func clearPending() { pendingP12 = nil; pendingName = ""; awaitingPassword = false }
    nonisolated private static func describe(_ error: Error) -> String {
        // Known credential messages contain no password/key bytes. Unknown errors are not dumped to logs/UI.
        (error as? CredentialError)?.errorDescription ?? "Import failed. Check the file and free space, then retry."
    }
}
