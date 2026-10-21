import Foundation

/// The one way this app talks to an install host. Error text stays at the call sites.
enum InstallTransport {
    static func send(_ request: URLRequest, session: URLSession) async throws -> (body: Data, code: Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func sendUpload(_ request: URLRequest, file: URL, session: URLSession, delegate: URLSessionTaskDelegate?) async throws -> (body: Data, code: Int) {
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func looksLikeManifest(_ data: Data) -> Bool {
        String(decoding: data.prefix(2048), as: UTF8.self).contains("<plist")
    }
}
