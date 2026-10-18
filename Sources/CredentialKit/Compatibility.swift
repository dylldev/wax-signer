import Foundation

public struct CompatibilityCheck: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case pass, fail, unknown }
    public let title: String
    public let status: Status
    public let detail: String
}

/// Result of static checks between one certificate and one profile.
/// It is not proof that installation will succeed.
public struct CompatibilityReport: Equatable, Sendable {
    public let checks: [CompatibilityCheck]

    public var hasFailures: Bool { checks.contains { $0.status == .fail } }

    public static let disclaimer =
        "These are static checks only. Passing them does not guarantee the app will install or run: "
        + "revocation, device registration, entitlement approval and the profile's Apple signature are not verified."

    public static func evaluate(certificate: CertificateInfo, profile: ProfileInfo, now: Date) -> CompatibilityReport {
        var checks: [CompatibilityCheck] = []

        let listed = profile.certificateSHA1s.contains(certificate.sha1Fingerprint)
        checks.append(.init(
            title: "Profile includes this certificate",
            status: listed ? .pass : .fail,
            detail: listed ? "The certificate is in the profile's developer certificate list."
                : "This certificate is not in the profile. Apps signed with it will not match the profile."))

        let teamMatch = certificate.teamID.map { $0 == profile.teamID }
        checks.append(.init(
            title: "Team ID matches",
            status: teamMatch == nil ? .unknown : (teamMatch! ? .pass : .fail),
            detail: teamMatch == nil ? "The certificate has no organizational unit to compare."
                : (teamMatch! ? "Both belong to team \(profile.teamID)."
                   : "Certificate team \(certificate.teamID!) differs from profile team \(profile.teamID).")))

        switch certificate.validity(at: now) {
        case .valid:
            checks.append(.init(title: "Certificate currently valid", status: .pass,
                                detail: "Valid until \(certificate.notAfter.formatted(date: .abbreviated, time: .omitted))."))
        case .expired:
            checks.append(.init(title: "Certificate currently valid", status: .fail, detail: "The certificate has expired."))
        case .notYetValid:
            checks.append(.init(title: "Certificate currently valid", status: .fail, detail: "The certificate is not valid yet."))
        }

        let expired = profile.isExpired(at: now)
        checks.append(.init(
            title: "Profile not expired", status: expired ? .fail : .pass,
            detail: expired ? "The profile has expired."
                : "Valid until \(profile.expirationDate.formatted(date: .abbreviated, time: .omitted))."))

        switch profile.kind {
        case .development, .adHoc:
            let n = profile.provisionedDeviceCount ?? 0
            checks.append(.init(
                title: "Device eligibility", status: .unknown,
                detail: "The profile provisions \(n) device\(n == 1 ? "" : "s"). Apps cannot read this device's "
                    + "UDID, so whether this device is one of them cannot be determined here."))
        case .enterprise:
            checks.append(.init(
                title: "Device eligibility", status: .unknown,
                detail: "Enterprise profile: not tied to specific devices. The profile must also be trusted on the device."))
        case .appStore:
            checks.append(.init(
                title: "Device eligibility", status: .fail,
                detail: "App Store distribution profile: apps signed with it cannot be installed outside the App Store."))
        }

        return CompatibilityReport(checks: checks)
    }
}
