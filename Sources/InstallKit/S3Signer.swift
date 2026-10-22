import Foundation
import CryptoKit

public struct S3Credentials: Equatable, Sendable {
    public var accessKey: String
    public var secretKey: String
    public var region: String
    public var endpoint: URL
    public init(accessKey: String, secretKey: String, region: String, endpoint: URL) {
        self.accessKey = accessKey; self.secretKey = secretKey; self.region = region; self.endpoint = endpoint
    }
}

/// AWS Signature Version 4 for S3-compatible buckets (AWS, Cloudflare R2, Backblaze B2, Oracle, MinIO).
public enum S3Signer {
    /// A link that lets anyone holding it GET this one object until it expires; nothing in the bucket is public.
    public static func presignGET(_ url: URL, credentials c: S3Credentials, expires: Int, date: Date) -> URL {
        let (stamp, day) = stamps(date)
        let scope = "\(day)/\(c.region)/s3/aws4_request"
        var query = existingQuery(url) + [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"), ("X-Amz-Credential", "\(c.accessKey)/\(scope)"),
            ("X-Amz-Date", stamp), ("X-Amz-Expires", String(expires)), ("X-Amz-SignedHeaders", "host"),
        ]
        query.sort { $0.0 < $1.0 }
        let canonicalQuery = query.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        let request = ["GET", canonicalPath(url), canonicalQuery, "host:\(hostHeader(url))\n", "host", "UNSIGNED-PAYLOAD"].joined(separator: "\n")
        let signature = sign(request, stamp: stamp, day: day, scope: scope, credentials: c)
        var parts = URLComponents(); parts.scheme = url.scheme; parts.host = url.host; parts.port = url.port
        parts.percentEncodedPath = canonicalPath(url)
        parts.percentEncodedQuery = canonicalQuery + "&X-Amz-Signature=\(signature)"
        return parts.url!
    }

    /// A request signed with headers. `headers` are extra headers to sign and send (for example `Content-Type`).
    public static func signedRequest(method: String, url: URL, payloadSHA256: String, credentials c: S3Credentials, date: Date,
                                     headers: [String: String] = [:]) -> URLRequest {
        let (stamp, day) = stamps(date)
        let scope = "\(day)/\(c.region)/s3/aws4_request"
        var all = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) })
        all["host"] = hostHeader(url); all["x-amz-content-sha256"] = payloadSHA256; all["x-amz-date"] = stamp
        let names = all.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(all[$0]!)\n" }.joined()
        let signedHeaders = names.joined(separator: ";")
        let query = existingQuery(url).sorted { $0.0 < $1.0 }.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        let request = [method, canonicalPath(url), query, canonicalHeaders, signedHeaders, payloadSHA256].joined(separator: "\n")
        let signature = sign(request, stamp: stamp, day: day, scope: scope, credentials: c)
        var r = URLRequest(url: url); r.httpMethod = method
        for (k, v) in all where k != "host" { r.setValue(v, forHTTPHeaderField: k) }
        r.setValue("AWS4-HMAC-SHA256 Credential=\(c.accessKey)/\(scope),SignedHeaders=\(signedHeaders),Signature=\(signature)",
                   forHTTPHeaderField: "Authorization")
        return r
    }

    private static func sign(_ canonicalRequest: String, stamp: String, day: String, scope: String, credentials c: S3Credentials) -> String {
        let toSign = "AWS4-HMAC-SHA256\n\(stamp)\n\(scope)\n" + hex(SHA256.hash(data: Data(canonicalRequest.utf8)))
        func mac(_ key: Data, _ message: String) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
        }
        let key = ["s3", "aws4_request"].reduce(mac(mac(Data(("AWS4" + c.secretKey).utf8), day), c.region)) { mac($0, $1) }
        return hex(mac(key, toSign))
    }

    private static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 { bytes.map { String(format: "%02x", $0) }.joined() }

    private static func stamps(_ date: Date) -> (String, String) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; let stamp = f.string(from: date)
        return (stamp, String(stamp.prefix(8)))
    }

    private static func hostHeader(_ url: URL) -> String {
        guard let host = url.host else { return "" }
        guard let port = url.port, !(url.scheme == "https" && port == 443), !(url.scheme == "http" && port == 80) else { return host }
        return "\(host):\(port)"
    }

    private static func existingQuery(_ url: URL) -> [(String, String)] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
    }

    /// S3 signs the path as sent, encoded once (no second round of encoding, unlike other AWS services).
    private static func canonicalPath(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return path.split(separator: "/", omittingEmptySubsequences: false).map { encode(String($0)) }.joined(separator: "/")
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s }
}
