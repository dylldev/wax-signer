import Foundation
import CryptoKit
import Security

/// Whether a provisioning profile's CMS signature checks out. Kept separate from structural validity:
/// a profile that parses is not thereby a profile Apple signed.
public enum ProfileSignatureStatus: Equatable {
    /// Signature and digest are valid and the signer's chain is trusted by the system and ends at a pinned Apple public root.
    case appleChainVerified(chain: [String])
    /// Cryptographically intact, but the signer is not shown to be Apple.
    case signatureValidButUntrusted(reason: String, chain: [String])
    /// The signature or digest does not match the content, or the CMS could not be read.
    case invalid(reason: String)
}

/// Verifies a `.mobileprovision` CMS signature using only public Security APIs.
///
/// Limits, all deliberate and stated here rather than hidden:
/// - Trust uses `SecPolicyCreateBasicX509` plus a check that the chain ends at a pinned Apple public root.
///   iOS itself applies an Apple-private profile-signing policy that is not public API.
/// - The chain is evaluated at the profile's signing time when present (the signing certificate is
///   short-lived), otherwise at `date`. iOS may not do the same.
/// - Revocation is not checked.
/// A result of `appleChainVerified` therefore means "looks Apple-signed", not "iOS will accept it".
public enum ProfileTrust {
    public static func evaluate(_ profile: Data, at date: Date = Date(), usingSigningTime: Bool = true) -> ProfileSignatureStatus {
        let cms: CMSSignedData
        do { cms = try CMSSignedData.parse(profile) } catch { return .invalid(reason: "not a readable CMS SignedData") }
        guard cms.signers.count == 1 else { return .invalid(reason: "expected exactly one signer, found \(cms.signers.count)") }

        switch cms.checkSignature() {
        case .invalid(let why): return .invalid(reason: why)
        case .valid: break
        }

        guard let leafDER = cms.signerCertificateDER(cms.signers[0]) else { return .invalid(reason: "signer certificate missing") }
        let certs = ([leafDER] + cms.certificatesDER.filter { $0 != leafDER }).compactMap {
            SecCertificateCreateWithData(nil, $0 as CFData)
        }

        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certs as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust else { return .signatureValidButUntrusted(reason: "CMS signature valid; chain evaluation unavailable", chain: []) }
        SecTrustSetVerifyDate(trust, ((usingSigningTime ? cms.signers[0].signingTime : nil) ?? date) as CFDate)

        var error: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &error)
        let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
        let chain = certificates.map { SecCertificateCopySubjectSummary($0) as String? ?? "?" }
        return classifyVerifiedCMS(trusted: trusted, rootDER: certificates.last.map { SecCertificateCopyData($0) as Data },
            chain: chain, reason: (error as Error?)?.localizedDescription ?? "chain not trusted")
    }

    /// Subject names are display metadata, never an issuer identity. These public root hashes were
    /// checked against Apple's HTTPS DER downloads and the engine's embedded public roots (2026-10-20).
    /// https://www.apple.com/appleca/AppleIncRootCertificate.cer
    /// https://www.apple.com/certificateauthority/AppleRootCA-G2.cer (and G3)
    static func classifyVerifiedCMS(trusted: Bool, rootDER: Data?, chain: [String], reason: String) -> ProfileSignatureStatus {
        let pins: Set<String> = [
            "b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024",
            "c2b9b042dd57830e7d117dac55ac8ae19407d38e41d88f3215bc3a890444a050",
            "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",
        ]
        let digest = rootDER.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
        if trusted, let digest, pins.contains(digest) { return .appleChainVerified(chain: chain) }
        return .signatureValidButUntrusted(reason: trusted ? "chain does not end at a pinned Apple root" : reason, chain: chain)
    }

}
