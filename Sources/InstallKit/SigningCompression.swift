import Foundation

/// How Wax packs the files it changed while signing. Unchanged files keep their original compressed bytes either way.
public enum SigningCompression: String, CaseIterable, Sendable {
    case standard, faster, largerFile

    public var title: String {
        switch self {
        case .standard: "Standard compression"
        case .faster: "Faster compression"
        case .largerFile: "Faster signing, larger file"
        }
    }

    public var detail: String {
        switch self {
        case .standard: "Smallest file."
        case .faster: "A little faster, a slightly bigger file."
        case .largerFile: "Changed files of 2 MB or more are not compressed: a much bigger file."
        }
    }

    /// What one signing run passes to the engine.
    public struct Flags: Equatable, Sendable {
        public var compressChangedFiles: Bool
        public var fastDeflate: Bool
        public init(compressChangedFiles: Bool, fastDeflate: Bool) {
            self.compressChangedFiles = compressChangedFiles; self.fastDeflate = fastDeflate
        }
    }

    public var flags: Flags {
        switch self {
        case .standard: Flags(compressChangedFiles: true, fastDeflate: false)
        case .faster: Flags(compressChangedFiles: true, fastDeflate: true)
        // Files under the 2 MiB cut-off are still compressed, at the faster level.
        case .largerFile: Flags(compressChangedFiles: false, fastDeflate: true)
        }
    }

    /// The saved choice. Until the person picks one, the two older switches keep their old meaning:
    /// exports are always standard, and only installs from this iPhone read the switches.
    public struct Preference {
        public static let explicitKey = "signing.compression"
        public static let legacyStoreKey = "storeUncompressed"
        public static let legacyFastKey = "fastDeflate"
        private let defaults: UserDefaults

        public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

        public var explicit: SigningCompression? {
            defaults.string(forKey: Self.explicitKey).flatMap(SigningCompression.init(rawValue:))
        }

        private var legacyStore: Bool { defaults.object(forKey: Self.legacyStoreKey) as? Bool ?? false }
        private var legacyFast: Bool { defaults.object(forKey: Self.legacyFastKey) as? Bool ?? true }

        /// What the picker shows: the saved choice, or the closest match to the older switches.
        public var selection: SigningCompression {
            if let explicit { return explicit }
            if legacyStore { return .largerFile }
            return legacyFast ? .faster : .standard
        }

        /// The line under the picker. Before a choice it describes what the saved older switches really do.
        public var note: String {
            let reuse = "Unchanged files keep their existing compression."
            guard explicit == nil else { return "Applies to future signing jobs, installs and exports alike. " + reuse }
            let phone: String
            if legacyStore { phone = "skip compression for changed files of 2 MB or more" }
            else { phone = legacyFast ? "use faster compression" : "use standard compression" }
            return "Not chosen yet: exports use standard compression and installs from this iPhone \(phone), as before. " + reuse
        }

        public func choose(_ mode: SigningCompression) { defaults.set(mode.rawValue, forKey: Self.explicitKey) }

        /// Read once when a signing run starts, so changing the setting cannot alter a run already under way.
        public func flags(phoneInstall: Bool) -> Flags {
            if let explicit { return explicit.flags }
            guard phoneInstall else { return SigningCompression.standard.flags }
            return Flags(compressChangedFiles: !legacyStore, fastDeflate: legacyFast)
        }
    }
}
