import XCTest
@testable import InstallKit

/// Inputs and signatures are the worked examples from AWS's "Signature Version 4" S3 documentation
/// (docs.aws.amazon.com, sig-v4-header-based-auth and sigv4-query-string-auth); re-checked against
/// those pages on 2026-10-18. No cross-check against an independent implementation exists.
final class S3SignerTests: XCTestCase {
    private let creds = S3Credentials(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                                      region: "us-east-1", endpoint: URL(string: "https://s3.amazonaws.com")!)
    private let date = Date(timeIntervalSince1970: 1369353600)   // 2013-05-24T00:00:00Z

    func testPresignedGetMatchesTheAWSExample() {
        let url = S3Signer.presignGET(URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!, credentials: creds, expires: 86400, date: date)
        XCTAssertEqual(url.absoluteString,
            "https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256"
            + "&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request"
            + "&X-Amz-Date=20130524T000000Z&X-Amz-Expires=86400&X-Amz-SignedHeaders=host"
            + "&X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
    }

    func testHeaderSignedGetMatchesTheAWSExample() throws {
        let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let r = S3Signer.signedRequest(method: "GET", url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!,
                                       payloadSHA256: empty, credentials: creds, date: date, headers: ["Range": "bytes=0-9"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"),
            "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
            + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,"
            + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-amz-date"), "20130524T000000Z")
        XCTAssertEqual(r.httpMethod, "GET")
    }

    func testPresignedURLIsPercentEncodedAndHasExpires() {
        let url = S3Signer.presignGET(URL(string: "https://b.example/ota/a b+c/app.ipa")!, credentials: creds, expires: 21600, date: date)
        let s = url.absoluteString
        XCTAssertTrue(s.contains("/ota/a%20b%2Bc/app.ipa?"), s)
        XCTAssertTrue(s.contains("X-Amz-Expires=21600"))
        XCTAssertFalse(s.contains("+"), "no raw plus: iOS and S3 would disagree about it")
    }
}
