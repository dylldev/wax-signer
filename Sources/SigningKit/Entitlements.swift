import CredentialKit
import Foundation

enum EntitlementsDER {
    /// `[APPLICATION 16] { INTEGER 1, [CONTEXT 16] { SEQUENCE { UTF8 key, value } ... } }`,
    /// the layout Apple's codesign emits (verified against its output for dict, array, int, bool, string).
    static func encode(_ dict: [String: Any]) throws -> Data {
        DER.tlv(0x70, DER.integer(1) + (try dictionary(dict)))
    }

    private static func dictionary(_ d: [String: Any]) throws -> Data {
        let members = try d.keys.sorted().map { key in
            DER.sequence([DER.utf8(key), try value(d[key]!)])
        }
        return DER.tlv(0xB0, members.reduce(Data(), +))
    }

    private static func value(_ v: Any) throws -> Data {
        switch v {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return DER.boolean(n.boolValue) }
            guard n.intValue >= 0 else { throw SigningError.bundle("negative integer entitlement") }
            return DER.integer(n.intValue)
        case let s as String: return DER.utf8(s)
        case let a as [Any]: return DER.sequence(try a.map(value))
        case let d as [String: Any]: return try dictionary(d)
        default: throw SigningError.bundle("unsupported entitlement value type \(type(of: v))")
        }
    }
}

/// Decides which entitlements an app is signed with, and says what it dropped.
struct EntitlementsPolicy {
    struct Result {
        var entitlements: [String: Any]
        var dropped: [String]
    }

    /// - `requested`: entitlements the app asked for (from its previous signature or caller).
    /// - `profile`: what the profile grants.
    /// Core identity entitlements always come from the profile; everything else the app requested is kept
    /// only if the profile grants that key. Nothing is added that the app did not ask for.
    static func resolve(requested: [String: Any], profile: [String: Any], teamID: String,
                        resolvedApplicationIdentifier: String, applicationIdentifierPrefix: String? = nil) -> Result {
        var out: [String: Any] = [
            "application-identifier": resolvedApplicationIdentifier,
            "com.apple.developer.team-identifier": teamID,
        ]
        if let taskAllow = profile["get-task-allow"] { out["get-task-allow"] = taskAllow }

        var dropped: [String] = []
        let identityKeys: Set<String> = ["application-identifier", "com.apple.developer.team-identifier", "get-task-allow"]
        for (key, value) in requested where !identityKeys.contains(key) {
            if key == "keychain-access-groups" {
                // Keychain groups follow the selected App ID prefix, not necessarily the Team ID.
                let groups = teamPrefixed((value as? [String]) ?? [], teamID: applicationIdentifierPrefix ?? teamID)
                if granted(key: key, value: groups, profile: profile) { out[key] = groups } else { dropped.append(key) }
            } else if granted(key: key, value: value, profile: profile) {
                out[key] = value
            } else {
                dropped.append(key)
            }
        }
        return Result(entitlements: out, dropped: dropped.sorted())
    }

    /// Requested entitlement keys the profile does not grant. A key is granted only if the profile has it
    /// and every requested value is permitted by it (list members must each match, wildcards end in `*`).
    static func unmet(requested: [String: Any], profile: [String: Any], teamID: String, applicationIdentifierPrefix: String? = nil) -> [String] {
        let derived: Set<String> = ["application-identifier", "com.apple.developer.team-identifier", "get-task-allow"]
        return requested.keys.filter { key in
            guard !derived.contains(key) else { return false }
            let value = key == "keychain-access-groups"
                ? teamPrefixed((requested[key] as? [String]) ?? [], teamID: applicationIdentifierPrefix ?? teamID) : requested[key]!
            return !granted(key: key, value: value, profile: profile)
        }.sorted()
    }

    /// Moves `keychain-access-groups` and `application-groups` values that name a renamed bundle (exactly or as a
    /// dotted parent, after a `TEAMID.` or `group.` prefix) onto the new identifier. Everything else is untouched.
    static func rewriteBundleScoped(_ requested: [String: Any], renames: [String: String]) -> [String: Any] {
        var out = requested
        let ordered = renames.sorted { $0.key.count > $1.key.count }
        for key in ["keychain-access-groups", "com.apple.security.application-groups"] {
            guard let values = requested[key] as? [String] else { continue }
            out[key] = values.map { value in
                var prefix = "", rest = value
                if let dot = value.firstIndex(of: "."), value[..<dot] == "group" || value[..<dot].range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil {
                    prefix = String(value[...dot]); rest = String(value[value.index(after: dot)...])
                }
                guard let (old, new) = ordered.first(where: { rest == $0.key || rest.hasPrefix($0.key + ".") }) else { return value }
                return prefix + new + rest.dropFirst(old.count)
            }
        }
        return out
    }

    /// Legacy helper name: moves keychain groups onto the supplied App ID prefix: a different 10-character team prefix is replaced, an
    /// unprefixed group gets the prefix. Groups already on `teamID` are untouched.
    static func teamPrefixed(_ groups: [String], teamID: String) -> [String] {
        groups.map { group in
            if group.hasPrefix(teamID + ".") { return group }
            if let old = group.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) {
                return teamID + "." + group[old.upperBound...]
            }
            return teamID + "." + group
        }
    }

    static func granted(key: String, value: Any, profile: [String: Any]) -> Bool {
        // Asking for `false` asks for nothing, so no grant is needed.
        if let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID(), !n.boolValue { return true }
        guard let allowed = profile[key] else { return false }
        func matches(_ want: String, _ have: String) -> Bool {
            have == want || (have.hasSuffix("*") && want.hasPrefix(String(have.dropLast())))
        }
        switch (value, allowed) {
        case (let want as [Any], let have as [Any]):
            let haveStrings = have.compactMap { $0 as? String }
            return want.allSatisfy { w in (w as? String).map { s in haveStrings.contains { matches(s, $0) } } ?? false }
        case (let want as NSNumber, let have as NSNumber)
            where CFGetTypeID(want) == CFBooleanGetTypeID() && CFGetTypeID(have) == CFBooleanGetTypeID():
            return !want.boolValue || have.boolValue
        case (let want as String, let have as String): return matches(want, have)
        default: return (value as AnyObject).isEqual(allowed)
        }
    }

    /// Whether a profile application identifier (`TEAM.com.x.app`, `TEAM.com.x.*`, `TEAM.*`) permits a bundle id.
    static func permits(profileApplicationIdentifier appID: String, teamID: String, bundleIdentifier: String) -> Bool {
        ProfileFitness.permits(bundleIdentifier: bundleIdentifier, profileApplicationIdentifier: appID, teamID: teamID)
    }
}
