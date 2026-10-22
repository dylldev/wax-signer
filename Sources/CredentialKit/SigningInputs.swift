import Foundation
import Security

/// A profile read for use by a signer: metadata plus the entitlements it grants.
/// Structural parse only. The profile's CMS signature is NOT verified, see `ProfileTrust`.
public struct ProvisioningProfile {
    public let info: ProfileInfo
    public let entitlements: [String: Any]
    public let rawData: Data

    public static func parse(_ data: Data, now: Date = Date()) throws -> ProvisioningProfile {
        let (info, entitlements) = try ProfileReader.readDetailed(data, importedAt: now, now: now)
        return ProvisioningProfile(info: info, entitlements: entitlements, rawData: data)
    }
}

/// An in-memory identity opened from a .p12. The private key stays inside the Security framework.
public struct LoadedIdentity {
    public let identity: SecIdentity
    public let certificateDER: Data
    public let teamID: String?
    public let commonName: String?

    public static func load(p12: Data, password: String) throws -> LoadedIdentity {
        let parsed = try PKCS12Reader.read(p12, password: password)
        return LoadedIdentity(identity: parsed.identity, certificateDER: parsed.certificateDER,
                              teamID: parsed.summary.organizationalUnit, commonName: parsed.summary.commonName)
    }
}

/// Validity period of an X.509 certificate (DER). iOS has no public API for this.
public enum CertificateValidity {
    public static func dates(of der: Data) -> (notBefore: Date, notAfter: Date)? {
        guard let s = try? X509Summary.parse(der: der) else { return nil }
        return (s.notBefore, s.notAfter)
    }
}

/// Subject common name of an X.509 certificate (DER).
public enum CertificateSubject {
    public static func commonName(of der: Data) -> String? {
        (try? X509Summary.parse(der: der))?.commonName
    }

    /// Subject OU, which is the Team ID for Apple-issued signing certificates.
    public static func teamID(of der: Data) -> String? {
        (try? X509Summary.parse(der: der))?.organizationalUnit
    }
}
