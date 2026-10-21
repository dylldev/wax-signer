import CoreGraphics
import Foundation
import ImageIO

/// Only the selected icon, not arbitrary app artwork. Limits are checked before decoding source pixels.
public enum BoundedIcon {
    public struct Limits: Sendable {
        public let maxBytes: Int
        public let maxPixels: Int64
        public let maxDimension: Int64
        public init(maxBytes: Int = 16 * 1024 * 1024, maxPixels: Int64 = 64 * 1024 * 1024, maxDimension: Int64 = 32_768) {
            self.maxBytes = maxBytes; self.maxPixels = maxPixels; self.maxDimension = maxDimension
        }
    }
    public enum Failure: LocalizedError, Equatable {
        case invalidLimits, tooLarge, dimensions, unreadable
        public var errorDescription: String? {
            switch self {
            case .invalidLimits: "The icon limits are invalid."
            case .tooLarge: "The chosen icon exceeds the image size limit. Choose a smaller image."
            case .dimensions: "The chosen icon has too many pixels or an unsupported size. Choose a smaller image."
            case .unreadable: "The chosen icon could not be read as an image. Choose another image."
            }
        }
    }
    /// Called inside the Photos transfer's temporary-file lease, on a worker. Never retains the provider URL.
    public static func prepare(file: URL, limits: Limits = Limits()) throws -> Data {
        try validate(limits); try Task.checkCancellation()
        guard file.isFileURL,
              (try FileManager.default.attributesOfItem(atPath: file.path)[.type]) as? FileAttributeType == .typeRegular else { throw Failure.unreadable }
        let input = try FileHandle(forReadingFrom: file); defer { try? input.close() }
        var bytes = Data()
        while let chunk = try input.read(upToCount: min(256 * 1024, limits.maxBytes + 1 - bytes.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= limits.maxBytes - bytes.count else { throw Failure.tooLarge }
            bytes.append(chunk)
        }
        return try prepare(data: bytes, limits: limits)
    }
    /// Returns a small PNG safe for both the preview and the signer's 120/152-pixel outputs.
    public static func prepare(data: Data, limits: Limits = Limits()) throws -> Data {
        let image = try thumbnail(data, limits: limits)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw Failure.unreadable }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        try Task.checkCancellation()
        return output as Data
    }
    static func thumbnail(_ data: Data, limits: Limits = Limits()) throws -> CGImage {
        try validate(limits); try Task.checkCancellation()
        guard data.count <= limits.maxBytes else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw Failure.unreadable }
        try validateDimensions(width: width.int64Value, height: height.int64Value, limits: limits)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 152,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { throw Failure.unreadable }
        try Task.checkCancellation()
        return image
    }
    static func validateDimensions(width: Int64, height: Int64, limits: Limits) throws {
        try validate(limits)
        guard width > 0, height > 0, width <= limits.maxDimension, height <= limits.maxDimension,
              width <= limits.maxPixels / height else { throw Failure.dimensions }
    }
    private static func validate(_ limits: Limits) throws {
        guard limits.maxBytes > 0, limits.maxBytes <= 32 * 1024 * 1024,
              limits.maxPixels > 0, limits.maxPixels <= 64 * 1024 * 1024,
              limits.maxDimension > 0, limits.maxDimension <= 32_768 else { throw Failure.invalidLimits }
    }
}
