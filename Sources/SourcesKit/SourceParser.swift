import Foundation

/// One downloadable app in a source, reduced to what Wax shows and needs.
public struct SourceApp: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleID: String
    public let version: String
    public let size: Int?
    public let iconURL: URL?
    public let downloadURL: URL
    public let date: Date?
    public let summary: String
    public let developer: String

    public init(id: String, name: String, bundleID: String, version: String, size: Int?, iconURL: URL?, downloadURL: URL,
                date: Date?, summary: String, developer: String) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.version = version; self.size = size
        self.iconURL = iconURL; self.downloadURL = downloadURL; self.date = date; self.summary = summary; self.developer = developer
    }
}

public struct SourceRepo: Codable, Equatable, Sendable {
    public var name: String
    public var apps: [SourceApp]
    public init(name: String, apps: [SourceApp]) { self.name = name; self.apps = apps }
}

public enum SourceError: Error, Equatable, LocalizedError {
    case notJSON, noApps
    public var errorDescription: String? {
        switch self {
        case .notJSON: "That address did not return a source file (it is not JSON). Check the link."
        case .noApps: "That file is JSON, but it does not list any apps, so it is not a source."
        }
    }
}

/// Reads AltStore/Feather-format sources in both layouts: `apps[].versions[]` (current) and app-level
/// `version`/`downloadURL` (older). Lenient by design: a malformed or download-less app is skipped, never fatal.
public enum SourceParser {
    public static func parse(_ data: Data) throws -> SourceRepo {
        let raw: Raw
        do { raw = try JSONDecoder().decode(Raw.self, from: data) } catch { throw SourceError.notJSON }
        guard let rawApps = raw.apps else { throw SourceError.noApps }

        var seen: [String: Int] = [:]
        var apps: [SourceApp] = []
        for item in rawApps {
            guard let a = item.value, let app = a.reduce() else { continue }
            let base = "\(app.bundleID)@\(app.version)"
            let n = seen[base, default: 0]; seen[base] = n + 1
            apps.append(n == 0 ? app.withID(base) : app.withID("\(base)#\(n)"))
        }
        return SourceRepo(name: raw.name ?? "Untitled source", apps: apps)
    }

    // MARK: Lenient decoding

    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// An Int that may arrive as a number, a numeric string, or null.
    private struct FlexInt: Decodable {
        let value: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { value = i }
            else if let d = try? c.decode(Double.self) { value = Int(exactly: d.rounded()) }   // nil for NaN, infinity and out-of-range: Int(d) would trap
            else if let s = try? c.decode(String.self) { value = Int(s) }
            else { value = nil }
        }
    }

    private struct Raw: Decodable {
        let name: String?
        let apps: [Failable<RawApp>]?
        enum Keys: String, CodingKey { case name, apps }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            apps = try? c.decodeIfPresent([Failable<RawApp>].self, forKey: .apps)
        }
    }

    private struct RawVersion: Decodable {
        var version: String?, date: String?, downloadURL: String?, size: Int?
        init() {}
        enum Keys: String, CodingKey { case version, date, downloadURL, size }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            version = try? c.decodeIfPresent(String.self, forKey: .version)
            date = try? c.decodeIfPresent(String.self, forKey: .date)
            downloadURL = try? c.decodeIfPresent(String.self, forKey: .downloadURL)
            size = (try? c.decodeIfPresent(FlexInt.self, forKey: .size))?.value
        }
    }

    private struct RawApp: Decodable {
        var name: String?, bundleID: String?, developer: String?, summary: String?, icon: String?
        var versions: [Failable<RawVersion>]?
        var legacy = RawVersion()
        enum Keys: String, CodingKey {
            case name, bundleIdentifier, developerName, localizedDescription, iconURL, versions, version, versionDate, downloadURL, size
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            name = try? c.decodeIfPresent(String.self, forKey: .name)
            bundleID = try? c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            developer = try? c.decodeIfPresent(String.self, forKey: .developerName)
            summary = try? c.decodeIfPresent(String.self, forKey: .localizedDescription)
            icon = try? c.decodeIfPresent(String.self, forKey: .iconURL)
            versions = try? c.decodeIfPresent([Failable<RawVersion>].self, forKey: .versions)
            legacy.version = try? c.decodeIfPresent(String.self, forKey: .version)
            legacy.date = try? c.decodeIfPresent(String.self, forKey: .versionDate)
            legacy.downloadURL = try? c.decodeIfPresent(String.self, forKey: .downloadURL)
            legacy.size = (try? c.decodeIfPresent(FlexInt.self, forKey: .size))?.value
        }

        func reduce() -> SourceApp? {
            guard let bundleID, !bundleID.isEmpty else { return nil }
            var candidates = (versions ?? []).compactMap(\.value)
            if legacy.downloadURL != nil { candidates.append(legacy) }
            let usable = candidates.compactMap { v -> (RawVersion, URL, Date?)? in
                guard let s = v.downloadURL, let url = URL(string: s), url.scheme == "https", url.host != nil else { return nil }
                return (v, url, v.date.flatMap(SourceParser.parseDate))
            }
            // Newest by date; when dates are missing the first listed wins (sources list newest first).
            guard let best = usable.enumerated().max(by: { a, b in
                switch (a.element.2, b.element.2) {
                case let (x?, y?): return x < y
                case (nil, _?): return true
                default: return a.offset > b.offset
                }
            })?.element else { return nil }
            return SourceApp(id: bundleID, name: name ?? bundleID, bundleID: bundleID, version: best.0.version ?? "",
                             size: best.0.size, iconURL: icon.flatMap(URL.init(string:)), downloadURL: best.1, date: best.2,
                             summary: summary ?? "", developer: developer ?? "")
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        let day = ISO8601DateFormatter(); day.formatOptions = [.withFullDate]
        return day.date(from: s)
    }
}

extension SourceApp {
    fileprivate func withID(_ id: String) -> SourceApp {
        SourceApp(id: id, name: name, bundleID: bundleID, version: version, size: size, iconURL: iconURL,
                  downloadURL: downloadURL, date: date, summary: summary, developer: developer)
    }
}
