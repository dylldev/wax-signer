import Foundation
import Security

/// Whether a provisioning profile's CMS signature checks out. Kept separate from structural validity:
/// a profile that parses is not thereby a profile Apple signed.
public enum ProfileSignatureStatus: Equatable {
    /// Signature and digest are valid and the signer's chain is trusted by the system and ends at "Apple Root CA".
    case appleChainVerified(chain: [String])
    /// Cryptographically intact, but the signer is not shown to be Apple.
    case signatureValidButUntrusted(reason: String, chain: [String])
    /// The signature or digest does not match the content, or the CMS could not be read.
    case invalid(reason: String)
}

/// Verifies a `.mobileprovision` CMS signature using only public Security APIs.
///
/// Limits, all deliberate and stated here rather than hidden:
/// - Trust uses `SecPolicyCreateBasicX509` plus a check that the chain ends at "Apple Root CA".
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
              let trust else { return .invalid(reason: "could not build a trust object") }
        SecTrustSetVerifyDate(trust, ((usingSigningTime ? cms.signers[0].signingTime : nil) ?? date) as CFDate)

        var error: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &error)
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? [])
            .map { SecCertificateCopySubjectSummary($0) as String? ?? "?" }

        if trusted, chain.last == "Apple Root CA" { return .appleChainVerified(chain: chain) }
        if trusted { return .signatureValidButUntrusted(reason: "chain ends at \(chain.last ?? "unknown"), not Apple Root CA", chain: chain) }
        let reason = (error as Error?)?.localizedDescription ?? "chain not trusted"
        return .signatureValidButUntrusted(reason: reason, chain: chain)
    }
}
