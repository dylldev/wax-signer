import Foundation
import Security

public enum SigningError: Error, Equatable, LocalizedError {
    case keyOperation(String)
    case unsupportedKeyType
    case machO(String)
    case bundle(String)
    case appIdentifierMismatch(bundle: String, id: String, profile: String)
    case profileDoesNotListCertificate
    case certificateExpired(Date)
    case certificateNotYetValid(Date)
    case profileTeamMismatch(profile: String, certificate: String)
    /// The identity supplied no usable certificate chain.
    case certificateChain(String)
    /// A profile that was pinned to a bundle (or the only one supplied) cannot be used for it.
    case profileRejected(bundle: String, profile: String, reason: String)
    /// Several profiles were considered for a bundle and none is usable. `reasons` has one line per profile.
    case noCompatibleProfile(bundle: String, id: String, reasons: [String])
    case io(String)
    /// The produced bundle did not pass the self-check; no output was written.
    case selfCheckFailed([String])

    public var errorDescription: String? {
        switch self {
        case .keyOperation(let m): return "Signing operation failed: \(m)"
        case .unsupportedKeyType: return "Only RSA signing keys are supported."
        case .machO(let m): return "Unsupported or malformed Mach-O: \(m)"
        case .bundle(let m): return "Bundle problem: \(m)"
        case .appIdentifierMismatch(let b, let id, let p):
            return "Bundle \(b) has identifier \(id), which the profile's application identifier \(p) does not permit."
        case .certificateExpired(let d): return "The signing certificate expired on \(d.formatted(date: .abbreviated, time: .omitted))."
        case .certificateNotYetValid(let d): return "The signing certificate is not valid until \(d.formatted(date: .abbreviated, time: .omitted))."
        case .profileDoesNotListCertificate: return "The provisioning profile does not list the signing certificate."
        case .profileTeamMismatch(let p, let c): return "Profile team \(p) differs from certificate team \(c)."
        case .certificateChain(let m): return "Certificate chain problem: \(m)"
        case .profileRejected(let b, let p, let r): return "Profile \"\(p)\" cannot sign \(b): \(r)."
        case .noCompatibleProfile(let b, let id, let reasons):
            let what = b == "." ? "the app" : b
            var text = "No imported profile can sign \(what) (\(id)): " + reasons.joined(separator: "; ") + "."
            if reasons.contains(where: { $0.contains("does not permit") }) {
                text += " This profile only allows one app ID. Choose “Rename to fit” in Settings, remove the app's extensions in "
                    + "Signing options, or import a wildcard profile."
            }
            return text
        case .selfCheckFailed(let f): return "The signed app failed its own consistency check, so no file was written: " + f.joined(separator: "; ")
        case .io(let m): return "I/O error: \(m)"
        }
    }
}

/// What the signer needs from a signing identity: certificates and a signing operation.
/// The private key is never exposed. The Security framework performs the signature.
public protocol CodeSigningIdentity {
    /// Leaf first, then intermediates, root last (root may be omitted).
    var certificateChainDER: [Data] { get }
    func signRSAPKCS1SHA256(_ message: Data) throws -> Data
}

public struct SecurityFrameworkIdentity: CodeSigningIdentity {
    private let key: SecKey
    public let certificateChainDER: [Data]

    public init(identity: SecIdentity, additionalCertificatesDER: [Data] = [], completeAppleChain: Bool = true) throws {
        var privateKey: SecKey?
        var cert: SecCertificate?
        guard SecIdentityCopyPrivateKey(identity, &privateKey) == errSecSuccess, let privateKey,
              SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else {
            throw SigningError.keyOperation("identity has no accessible private key")
        }
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw SigningError.unsupportedKeyType
        }
        key = privateKey
        let supplied = [SecCertificateCopyData(cert) as Data] + additionalCertificatesDER
        certificateChainDER = completeAppleChain ? AppleCertificateAuthorities.complete(chain: supplied) : supplied
    }

    public func signRSAPKCS1SHA256(_ message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) else {
            throw SigningError.keyOperation(error?.takeRetainedValue().localizedDescription ?? "unknown")
        }
        return sig as Data
    }
}
