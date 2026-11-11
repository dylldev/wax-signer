import CredentialKit
import InstallKit
import IPAKit
import Security
import SigningKit
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import LocalIPASigner

private struct PresentationSecrets: SecretStore {
    func load() -> Data? { Data(String(repeating: "t", count: 40).utf8) }
    func save(_ data: Data) throws {}
    func delete() {}
}
private final class PresentationKeychain: IdentityKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: SecIdentity] = [:]
    func store(identity: SecIdentity, id: UUID) throws { lock.lock(); defer { lock.unlock() }; items[id] = identity }
    func identity(id: UUID) throws -> SecIdentity {
        lock.lock(); defer { lock.unlock() }
        guard let identity = items[id] else { throw CredentialError.notFound }
        return identity
    }
    func remove(id: UUID) throws { lock.lock(); defer { lock.unlock() }; items[id] = nil }
}
private actor PresentationGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var released = false
    func wait() async -> Bool {
        if released { return true }
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(returning: true); continuation = nil }
}
private struct PresentationPublisher: InstallHost {
    func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(1)
        return URL(string: "itms-services://?action=download-manifest&url=https://fixture.example/manifest")!
    }
}

@MainActor
final class SignPresentationTests: XCTestCase {
    private var root: URL!
    private var credentials: CredentialsModel!
    private var signer: SigningModel!
    private var ota: OTAInstallModel!
    private var window: UIWindow?
    private var previous: [String: Any] = [:]
    private let keys = ["installHost", "otaServer", "certificateFeed"]

    override func setUp() async throws {
        for key in keys { previous[key] = UserDefaults.standard.object(forKey: key) }
        root = FileManager.default.temporaryDirectory.appendingPathComponent("sign-presentation-\(UUID())")
        let store = try CredentialStore(directory: root.appendingPathComponent("Credentials"), keychain: PresentationKeychain())
        let certificate = try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        try store.importProfile(FixtureData.profileWildcardAll)
        credentials = CredentialsModel(store: store)
        let library = LibraryModel(library: IPALibrary(root: root.appendingPathComponent("Shelf")), load: false)
        signer = SigningModel(credentials: credentials, library: library)
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TestApp", withExtension: "ipa"))
        let input = root.appendingPathComponent("input.ipa")
        try FileManager.default.copyItem(at: fixture, to: input)
        signer.picked(ipa: input)
        for _ in 0..<500 where signer.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(signer.ipaInfo, signer.errorText ?? "IPA not loaded")
        signer.certificateID = certificate.id
        ota = OTAInstallModel(store: PresentationSecrets(), bucketStore: PresentationSecrets(),
                              cleanupStore: BucketCleanupStore(file: root.appendingPathComponent("journal")), sweepOnStart: false)
        ota.hostKind = .server; ota.serverText = ""
    }
    override func tearDown() async throws {
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        signer.cancelInstallation(ota: ota)
        for key in keys { UserDefaults.standard.set(previous[key], forKey: key) }
        try? FileManager.default.removeItem(at: root)
    }

    private func render() async throws -> [String] {
        let view = SignView(inbox: InstallInbox()).environmentObject(signer).environmentObject(credentials)
            .environmentObject(Router()).environmentObject(ota)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible(); self.window = window
        try await Task.sleep(for: .milliseconds(250))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: try XCTUnwrap(image.cgImage)).perform([request])
        let labels = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        XCTAssertFalse(labels.isEmpty, "The rendered screen must contain readable text")
        return labels
    }

    func testExportRemainsAvailableWithoutInstallHost() async throws {
        XCTAssertTrue(signer.canSign); XCTAssertFalse(ota.isConfigured)
        let labels = try await render()
        XCTAssertTrue(labels.contains { $0.contains("Set up installation") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Sign only and export") }, "A host is unnecessary for export: \(labels)")
    }

    func testExportStillRequiresAProvisioningProfile() async throws {
        let store = try XCTUnwrap(credentials.store)
        for profile in credentials.profiles { try store.deleteProfile(id: profile.id) }
        credentials = CredentialsModel(store: store)
        XCTAssertTrue(signer.canSign); XCTAssertTrue(credentials.profiles.isEmpty)
        let labels = try await render()
        XCTAssertTrue(labels.contains { $0.contains("Import a profile") }, "\(labels)")
        XCTAssertFalse(labels.contains { $0.contains("Sign only and export") }, "\(labels)")
    }

    func testSlowHostPreparationKeepsTheUploadHalfIncomplete() async throws {
        let gate = PresentationGate(), preparing = expectation(description: "host preparation started")
        ota = OTAInstallModel(store: PresentationSecrets(), bucketStore: PresentationSecrets(),
            cleanupStore: BucketCleanupStore(file: root.appendingPathComponent("slow-journal")), sweepOnStart: false,
            prepareServer: { _, _ in
                preparing.fulfill(); _ = await gate.wait()
                return .init(publisher: PresentationPublisher())
            })
        ota.hostKind = .server; ota.serverText = "https://fixture.example"
        let task = Task { await signer.signAndInstall(ota: ota) { _ in } }
        await fulfillment(of: [preparing], timeout: 15)
        let labels: [String]
        do { labels = try await render() }
        catch { await gate.release(); await task.value; throw error }
        let signed = signer.report != nil && ota.state == .preparing
        await gate.release(); await task.value
        XCTAssertTrue(signed, "The test must pause between signing and upload")
        XCTAssertTrue(labels.contains { $0.replacingOccurrences(of: " ", with: "") == "50%" }, "\(labels)")
        XCTAssertFalse(labels.contains { $0.replacingOccurrences(of: " ", with: "") == "100%" }, "\(labels)")
    }

    func testHostReservationDoesNotShowCompletedSigningOrUpload() async throws {
        ota.serverText = "https://fixture.example"
        let session = try ota.reserve(); defer { ota.release(session) }
        XCTAssertNil(signer.report); XCTAssertEqual(signer.signFraction, 0)
        let labels = try await render()
        XCTAssertFalse(labels.contains { $0.replacingOccurrences(of: " ", with: "") == "100%" }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.replacingOccurrences(of: " ", with: "") == "0%" }, "\(labels)")
    }

    func testPhoneHandoffKeepsRetryAndStayOpenVisible() async throws {
        let gate = PresentationGate(), opened = expectation(description: "installer opened")
        ota = OTAInstallModel(store: PresentationSecrets(), bucketStore: PresentationSecrets(),
            cleanupStore: BucketCleanupStore(file: root.appendingPathComponent("phone-journal")), sweepOnStart: false,
            preparePhone: { _ in .init(publisher: PresentationPublisher(), wait: { _ in await gate.wait() }) })
        ota.hostKind = .phone; ota.certificateFeedText = "https://fixture.example/feed.json"
        let task = Task { await signer.signAndInstall(ota: ota) { _ in opened.fulfill() } }
        await fulfillment(of: [opened], timeout: 15)
        let labels: [String]
        do { labels = try await render() }
        catch { await gate.release(); await task.value; throw error }
        let waiting = signer.installing && ota.state == .handedToiOS
        await gate.release(); await task.value
        XCTAssertTrue(waiting, "The test must inspect an active phone transfer")
        XCTAssertTrue(labels.contains { $0.contains("Open install again") }, "\(labels)")
        XCTAssertTrue(labels.contains { $0.contains("Keep Wax open") }, "\(labels)")
    }
}
