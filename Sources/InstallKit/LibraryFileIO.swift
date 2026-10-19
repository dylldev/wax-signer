import CryptoKit
import Foundation

/// Library-specific streaming I/O. No dependency on the ZIP/signing packages.
enum LibraryFileIO {
    struct Digest: Equatable { let sha256: String; let size: Int }
    static let chunkSize = 256 * 1024

    static func hash(_ url: URL, read: (() throws -> Void)? = nil) throws -> Digest {
        try stream(url, read: read, emit: { _ in })
    }

    static func copy(_ source: URL, to destination: URL, checkpoint: @escaping (IPALibrary.Checkpoint, URL) throws -> Void) throws -> Digest {
        try checkpoint(.beforeCopy, destination)
        let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw LibraryError.io("Creating the staged copy", String(cString: strerror(errno))) }
        let out = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? out.close() }
        let copied = try stream(source, read: { try checkpoint(.hashRead, source) }) { data in
            try checkpoint(.copyChunk, destination)
            try out.write(contentsOf: data)
        }
        try out.synchronize(); try out.close()
        try checkpoint(.afterCopy, destination)
        let verified = try hash(destination, read: { try checkpoint(.hashRead, destination) })
        guard verified == copied else { throw LibraryError.changed("The staged copy did not match its input") }
        // A file changing after its copy must not be represented by stale inspection/hash metadata.
        guard try hash(source, read: { try checkpoint(.hashRead, source) }) == copied else { throw LibraryError.changed("The source changed during saving") }
        return copied
    }

    private static func stream(_ url: URL, read: (() throws -> Void)?, emit: (Data) throws -> Void) throws -> Digest {
        guard url.isFileURL else { throw LibraryError.unsafeFile("expected a local file URL") }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw LibraryError.io("Reading \(url.lastPathComponent)", String(cString: strerror(errno))) }
        let input = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? input.close() }
        var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, before.st_mode & 0o170000 == 0o100000, before.st_size >= 0,
              UInt64(before.st_size) <= UInt64(Int.max) else { throw LibraryError.unsafeFile(url.lastPathComponent) }
        var digest = SHA256(), size = 0
        while true {
            try read?()
            guard let data = try input.read(upToCount: chunkSize), !data.isEmpty else { break }
            guard data.count <= Int(before.st_size) - size else { throw LibraryError.changed("A file grew during saving") }
            digest.update(data: data); size += data.count; try emit(data)
        }
        guard size == Int(before.st_size), fstat(fd, &after) == 0, before.st_size == after.st_size else {
            throw LibraryError.changed("A file was truncated during saving")
        }
        #if canImport(Darwin)
        let stable = before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec
            && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec
        #else
        let stable = before.st_mtim.tv_sec == after.st_mtim.tv_sec && before.st_mtim.tv_nsec == after.st_mtim.tv_nsec
            && before.st_ctim.tv_sec == after.st_ctim.tv_sec && before.st_ctim.tv_nsec == after.st_ctim.tv_nsec
        #endif
        guard stable else { throw LibraryError.changed("A file changed while being read") }
        try input.close()
        return Digest(sha256: digest.finalize().map { String(format: "%02x", $0) }.joined(), size: size)
    }
}
