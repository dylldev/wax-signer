import CredentialKit
import Foundation

/// What the Passport needs to know about one selected profile to talk about devices and revocation.
struct ProfileEligibility: Equatable {
    let kind: ProfileKind
    let provisionsAllDevices: Bool
    let deviceCount: Int?
}

/// Passport wording that fits both free development profiles and enterprise (In-House) profiles.
enum EligibilityFindings {
    static func deviceMembership(for profiles: [ProfileEligibility]) -> PreflightFinding {
        if !profiles.isEmpty, profiles.allSatisfy({ $0.provisionsAllDevices }) {
            return PreflightFinding(id: "device-membership", status: .pass, title: "Works on any iPhone, once trusted",
                                    detail: "The selected Enterprise profile has no device list, so this iPhone does not need to be registered. "
                                        + "The first time, trust the developer in Settings ▸ General ▸ VPN & Device Management.")
        }
        let counts = profiles.compactMap { $0.deviceCount }
        let listed = counts.max().map { " The selected profile lists \($0) device\($0 == 1 ? "" : "s")." } ?? ""
        return PreflightFinding(id: "device-membership", status: .unknown, title: "Device eligibility cannot be checked",
                                detail: "Wax cannot read this iPhone's UDID through public app APIs, so it cannot confirm this iPhone is on the profile's device list." + listed)
    }

    static func revocation(for profiles: [ProfileEligibility]) -> PreflightFinding {
        if profiles.contains(where: { $0.kind == .enterprise }) {
            return PreflightFinding(id: "revocation", status: .unknown, title: "Current revocation status is unknown",
                                    detail: "Enterprise certificates can be revoked by Apple or by their owner at any time, long before they expire, and the app then stops opening. Wax cannot see revocation; if the app stops launching, sign it again with a different certificate.")
        }
        return PreflightFinding(id: "revocation", status: .unknown, title: "Current revocation status is unknown",
                                detail: "Wax does not have a current Apple revocation decision.")
    }
}
