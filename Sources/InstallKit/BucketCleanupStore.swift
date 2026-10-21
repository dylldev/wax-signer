import CryptoKit
import Foundation

/// Public connection metadata only. Credentials remain in Keychain and are never written to this journal.
public struct BucketCleanupScope: Codable, Hashable, Sendable {
    public let endpoint: URL
    public let bucket: String
    public let region: String
    public let accessKeySHA256: String

    public init(credentials: S3Credentials, bucket: String) throws {
        endpoint = try OTAEndpoint(credentials.endpoint.absoluteString).base
        guard !bucket.isEmpty, !bucket.contains("/"), !bucket.contains("\\"), bucket != ".", bucket != "..",
              !credentials.region.isEmpty, !credentials.accessKey.isEmpty else {
            throw BucketCleanupStore.Failure.invalidRecord
        }
        self.bucket = bucket; region = credentials.region
        accessKeySHA256 = SHA256.hash(data: Data(credentials.accessKey.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct BucketCleanupRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let scope: BucketCleanupScope
    /// nil means publication was not acknowledged to the app; never hand off an install link in this state.
    public var expiresAt: Date?
    public init(sessionID: String, scope: BucketCleanupScope, expiresAt: Date? = nil) throws {
        guard sessionID.utf8.count == 22,
              sessionID.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw BucketCleanupStore.Failure.invalidRecord
        }
        id = UUID(); self.sessionID = sessionID; self.scope = scope; self.expiresAt = expiresAt
    }
}

/// Small atomic index, serialized per store instance. One app-owned store per file; no cross-process claim.
/// A failed/corrupt index is preserved and blocks new uploads rather than forgetting deletion obligations.
public final class BucketCleanupStore: @unchecked Sendable {
    public enum Failure: Error, LocalizedError {
        case invalidRecord, invalidIndex
        public var errorDescription: String? {
            switch self {
            case .invalidRecord: return "The bucket cleanup destination is invalid. Check the endpoint and bucket settings."
            case .invalidIndex: return "Bucket cleanup records could not be read. They were preserved; recover them before uploading again."
            }
        }
    }
    private struct Route: Hashable { let scope: BucketCleanupScope; let sessionID: String }
    private struct Index: Codable { var version = 1; var records: [BucketCleanupRecord] }
    private let file: URL
    private let lock = NSLock()
    public init(file: URL) { self.file = file }
    public func records() throws -> [BucketCleanupRecord] { try locked { try read() } }
    public func put(_ record: BucketCleanupRecord) throws {
        try locked {
            var records = try read()
            guard !records.contains(where: { $0.id != record.id && $0.scope == record.scope && $0.sessionID == record.sessionID }) else { throw Failure.invalidRecord }
            records.removeAll { $0.id == record.id }; records.append(record)
            try write(records)
        }
    }
    public func remove(_ record: BucketCleanupRecord) throws {
        try locked {
            let records = try read()
            // Never remove a newer expiry written while an earlier cleanup was in flight.
            try write(records.filter { $0 != record })
        }
    }
    private func read() throws -> [BucketCleanupRecord] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 4 * 1024 * 1024 else { throw Failure.invalidIndex }
        let index: Index
        do { index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: file)) } catch { throw Failure.invalidIndex }
        guard index.version == 1, index.records.count <= 10_000,
              Set(index.records.map(\.id)).count == index.records.count,
              Set(index.records.map { Route(scope: $0.scope, sessionID: $0.sessionID) }).count == index.records.count else { throw Failure.invalidIndex }
        for record in index.records {
            // Codable synthesis bypasses initializers; validate persisted routing data before using it.
            guard let components = URLComponents(url: record.scope.endpoint, resolvingAgainstBaseURL: false),
                  components.user == nil, components.password == nil,
                  (try? OTAEndpoint(record.scope.endpoint.absoluteString))?.base == record.scope.endpoint,
                  record.scope.accessKeySHA256.utf8.count == 64,
                  record.scope.accessKeySHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  !record.scope.bucket.isEmpty, !record.scope.bucket.contains("/"), !record.scope.bucket.contains("\\"),
                  record.scope.bucket != ".", record.scope.bucket != "..", !record.scope.region.isEmpty else { throw Failure.invalidIndex }
            _ = try BucketCleanupRecord(sessionID: record.sessionID, scope: record.scope)
        }
        return index.records
    }
    private func write(_ records: [BucketCleanupRecord]) throws {
        guard records.count <= 10_000 else { throw Failure.invalidIndex }
        let data = try JSONEncoder().encode(Index(records: records))
        guard data.count <= 4 * 1024 * 1024 else { throw Failure.invalidIndex }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var journal = file; try journal.setResourceValues(resource)
    }
    private func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
}
