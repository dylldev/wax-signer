import Foundation

/// One number for the whole job. Signing and uploading each report their own real 0...1 progress; this joins them
/// in proportion to how long each is expected to take, so the total moves evenly instead of jumping at the seam.
public struct JobProgress: Equatable, Sendable {
    public let signSeconds: Double
    public let uploadSeconds: Double

    public init(signSeconds: Double, uploadSeconds: Double) {
        self.signSeconds = max(0, signSeconds.isFinite ? signSeconds : 0)
        self.uploadSeconds = max(0, uploadSeconds.isFinite ? uploadSeconds : 0)
    }

    public func overall(sign: Double, upload: Double) -> Double {
        let total = signSeconds + uploadSeconds
        guard total > 0 else { return clamp(sign) }
        return (signSeconds * clamp(sign) + uploadSeconds * clamp(upload)) / total
    }

    private func clamp(_ v: Double) -> Double { v.isFinite ? min(1, max(0, v)) : 0 }
}

/// Where the estimator keeps what it has learned.
public protocol EstimateStore: AnyObject {
    func double(forKey key: String) -> Double?
    func set(_ value: Double, forKey key: String)
}

public final class InMemoryEstimateStore: EstimateStore {
    private var values: [String: Double] = [:]
    public init() {}
    public func double(forKey key: String) -> Double? { values[key] }
    public func set(_ value: Double, forKey key: String) { values[key] = value }
}

extension UserDefaults: EstimateStore {
    public func double(forKey key: String) -> Double? { object(forKey: key) as? Double }
    public func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
}

/// Learns seconds per megabyte for signing and for uploading from finished runs (a smoothed average), so the
/// next run's progress is weighted by how this phone and this network really behave.
public struct JobEstimator {
    private let store: EstimateStore
    private static let signKey = "wax.estimate.signSecondsPerMB"
    private static let uploadKey = "wax.estimate.uploadSecondsPerMB"
    // Starting guesses: about 0.08 s/MB to sign on a phone, about 12 MB/s upload.
    private static let defaultSign = 0.08
    private static let defaultUpload = 1.0 / 12.0

    public init(store: EstimateStore) { self.store = store }

    public func estimate(megabytes: Double) -> (sign: Double, upload: Double) {
        let mb = max(0, megabytes.isFinite ? megabytes : 0)
        return (mb * (store.double(forKey: Self.signKey) ?? Self.defaultSign),
                mb * (store.double(forKey: Self.uploadKey) ?? Self.defaultUpload))
    }

    public mutating func record(megabytes: Double, signSeconds: Double, uploadSeconds: Double) {
        guard megabytes.isFinite, megabytes > 0.5 else { return }
        blend(Self.signKey, signSeconds / megabytes, fallback: Self.defaultSign)
        blend(Self.uploadKey, uploadSeconds / megabytes, fallback: Self.defaultUpload)
    }

    private func blend(_ key: String, _ measured: Double, fallback: Double) {
        guard measured.isFinite, measured > 0 else { return }
        let old = store.double(forKey: key) ?? fallback
        store.set(old * 0.5 + measured * 0.5, forKey: key)
    }
}
