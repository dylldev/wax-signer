import CredentialKit
import Foundation

/// Frozen, read-only decisions for a prepared unpacked app. This is not an iOS trust/install approval.
/// Public values contain no keys or signing handles. Values are XML bytes rather than mutable Any containers.
public struct SigningPlan {
    public enum ProfilePolicy {
        /// Reject invalid CMS; valid-but-untrusted remains explicitly distinct from Apple-chain verification.
        case requireValidCMS
        /// Only for synthetic fixtures/research; never evidence of legitimate device provisioning.
        case allowInvalidForTesting
    }
    public struct Entitlement {
        public enum Disposition: String { case granted, rewritten, dropped, identityAdded }
        public let key: String
        public let disposition: Disposition
        /// XML dictionary with one `value` key; nil means absent.
        public let requestedValueXML: Data?
        public let signedValueXML: Data?
    }
    public struct Bundle {
        public let path: String
        public let originalIdentifier: String
        public let identifier: String
        public let profile: ProfileSelection
        public let entitlements: [Entitlement]
        public let requestedEntitlementsXML: Data
        public let signedEntitlementsXML: Data
    }
    public let bundles: [Bundle]
    public let identifierChanges: [String: String]
    public let installationAssessment = "Not determined. Local planning does not evaluate iOS installation, revocation or launch."
    private let execution: Execution
    init(bundles: [Bundle], identifierChanges: [String: String], operation: @escaping (CodeSigningIdentity, Date) throws -> SigningResult) {
        self.bundles = bundles; self.identifierChanges = identifierChanges; self.execution = Execution(operation)
    }
    func execute(identity: CodeSigningIdentity, now: Date) throws -> SigningResult { try execution.run(identity, now) }
    private final class Execution {
        let lock = NSLock()
        var consumed = false
        let operation: (CodeSigningIdentity, Date) throws -> SigningResult
        init(_ operation: @escaping (CodeSigningIdentity, Date) throws -> SigningResult) { self.operation = operation }
        func run(_ identity: CodeSigningIdentity, _ now: Date) throws -> SigningResult {
            try lock.withLock {
                guard !consumed else { throw SigningError.bundle("preflight plan was already attempted; create a new plan") }
                consumed = true
                return try operation(identity, now)
            }
        }
    }
}
