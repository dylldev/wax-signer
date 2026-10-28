import CredentialKit
import InstallKit
import IPAKit
import SourcesKit
import XCTest
import UIKit
@testable import LocalIPASigner

@MainActor
final class LibraryOutcomeTests: XCTestCase {
    private var base: URL!
    private var library: LibraryModel!
    private var announcements: [String] = []
    private var root: URL { base.appendingPathComponent("shelf") }
    private var fixture: URL { Bundle(for: Self.self).url(forResource: "TestApp", withExtension: "ipa")! }
    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("model-library-\(UUID())")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        library = LibraryModel(library: IPALibrary(root: root), announce: { [weak self] in self?.announcements.append($0) }, load: false)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }
    private func blockIndex() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("index.json"), withIntermediateDirectories: true)
    }
    private func unblockIndex() throws { try FileManager.default.removeItem(at: root.appendingPathComponent("index.json")) }
    private func signingModel() throws -> SigningModel {
        SigningModel(credentials: CredentialsModel(store: try CredentialStore(directory: base.appendingPathComponent("credentials"))), library: library)
    }
    private func failure(_ operation: () async throws -> Void) async -> ShelfSaveFailure? {
        do { try await operation(); XCTFail("expected a storage failure"); return nil }
        catch let error as ShelfSaveFailure { return error }
        catch { XCTFail("expected recoverable save failure, got \(error)"); return nil }
    }
    private func pickedCopy() throws -> URL {
        let url = base.appendingPathComponent("picked-\(UUID()).ipa")
        try FileManager.default.copyItem(at: fixture, to: url); return url
    }
    private func signedInstallEntry() async throws -> LibraryEntry {
        let tree = base.appendingPathComponent("install-tree-\(UUID())")
        try IPAExtractor.extract(ipa: fixture, to: tree)
        let info = try IPAInspector.inspect(url: fixture)
        let app = tree.appendingPathComponent("Payload/" + info.appFolder)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("_CodeSignature"), withIntermediateDirectories: true)
        try Data("synthetic marker; iOS validates signatures".utf8).write(to: app.appendingPathComponent("_CodeSignature/CodeResources"))
        try Data("synthetic profile marker".utf8).write(to: app.appendingPathComponent("embedded.mobileprovision"))
        let file = base.appendingPathComponent("install-\(UUID()).ipa")
        try IPAArchiver.archive(directory: tree, to: file)
        return try await library.fileNow(file, info: IPAInspector.inspect(url: file), signed: true).entry
    }
    private func installer(_ publish: @escaping @Sendable (URL) throws -> Void) -> OTAInstallModel {
        let ota = OTAInstallModel(store: ShelfInstallSecrets(), bucketStore: ShelfInstallSecrets(),
            cleanupStore: BucketCleanupStore(file: base.appendingPathComponent("install-journal")), sweepOnStart: false,
            prepareServer: { _, _ in .init(publisher: ShelfInstallPublisher(check: publish)) })
        ota.hostKind = .server; ota.serverText = "https://fixture.example"
        return ota
    }
    func testSavedInstallUploadsSnapshotWithoutSigningOrChangingSelectedInput() async throws {
        let entry = try await signedInstallEntry(), model = try signingModel()
        model.use(library.signed[0])
        for _ in 0..<200 where model.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        let name = model.ipaName, info = model.ipaInfo?.bundleIdentifier, certificate = UUID()
        model.certificateID = certificate
        let shelfURL = library.url(for: entry), expected = try Data(contentsOf: shelfURL)
        let uploaded = expectation(description: "exact committed bytes uploaded")
        let ota = installer { url in
            XCTAssertNotEqual(url, shelfURL)
            XCTAssertEqual(try Data(contentsOf: url), expected); uploaded.fulfill()
        }
        await model.installSaved(entry, ota: ota, open: { _ in })
        await fulfillment(of: [uploaded], timeout: 2)
        XCTAssertEqual(model.certificateID, certificate); XCTAssertEqual(model.ipaName, name)
        XCTAssertEqual(model.ipaInfo?.bundleIdentifier, info); XCTAssertNil(model.report)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: entry).path))
        XCTAssertNil(model.savedInstallError); XCTAssertFalse(model.installing); XCTAssertNil(ota.activeSession)
    }
    func testStartingOverClearsTheSavedInstallError() async throws {
        let model = try signingModel(), ota = installer { _ in XCTFail("invalid artifact published") }
        let unsigned = try await library.importPicked(pickedCopy()).entry
        await model.installSaved(unsigned, ota: ota, open: { _ in XCTFail() })
        XCTAssertNotNil(model.savedInstallError)
        model.clearResult()
        XCTAssertNil(model.savedInstallError)
    }
    func testSavedInstallRejectsUnsignedCorruptMissingAndUnsignedMarkers() async throws {
        let model = try signingModel(), ota = installer { _ in XCTFail("invalid artifact published") }
        let unsigned = try await library.importPicked(pickedCopy()).entry
        await model.installSaved(unsigned, ota: ota, open: { _ in XCTFail() }); XCTAssertNotNil(model.savedInstallError)
        let noMarkers = try await library.fileNow(fixture, info: IPAInspector.inspect(url: fixture), signed: true).entry
        await model.installSaved(noMarkers, ota: ota, open: { _ in XCTFail() }); XCTAssertNotNil(model.savedInstallError)
        let signed = try await signedInstallEntry(), file = library.url(for: signed)
        try Data("corrupted".utf8).write(to: file)
        await model.installSaved(signed, ota: ota, open: { _ in XCTFail() }); XCTAssertNotNil(model.savedInstallError)
        try FileManager.default.removeItem(at: file)
        await model.installSaved(signed, ota: ota, open: { _ in XCTFail() }); XCTAssertNotNil(model.savedInstallError)
        XCTAssertFalse(model.installing); XCTAssertNil(ota.activeSession)
    }
    func testSavedInstallCannotTakeProbeReservation() async throws {
        let entry = try await signedInstallEntry(), model = try signingModel()
        let ota = installer { _ in XCTFail("busy host published") }, probe = try ota.reserve()
        await model.installSaved(entry, ota: ota, open: { _ in XCTFail() })
        XCTAssertTrue(ota.owns(probe)); XCTAssertFalse(model.installing); XCTAssertNotNil(model.savedInstallError)
        ota.release(probe)
    }
    func testSavedInstallSnapshotLivesThroughPhoneDeliveryAndPickingAnotherApp() async throws {
        let entry = try await signedInstallEntry(), model = try signingModel()
        let entered = expectation(description: "phone delivery"), gate = ShelfInstallGate(), publisher = ShelfCapturePublisher()
        let ota = OTAInstallModel(store: ShelfInstallSecrets(), bucketStore: ShelfInstallSecrets(), sweepOnStart: false,
            preparePhone: { _ in .init(publisher: publisher, wait: { _ in entered.fulfill(); await gate.wait(); return true }) })
        ota.hostKind = .phone; ota.certificateFeedText = "https://fixture.example/cert.json"
        let installation = Task { await model.installSaved(entry, ota: ota, open: { _ in }) }
        await fulfillment(of: [entered], timeout: 5)
        let captured = await publisher.path(), snapshot = try XCTUnwrap(captured)
        let expected = try Data(contentsOf: snapshot), link = try XCTUnwrap(model.readyLink)
        await library.remove(entry)
        model.picked(ipa: try pickedCopy())
        for _ in 0..<200 where model.busyMessage != nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(try Data(contentsOf: snapshot), expected)
        XCTAssertTrue(model.canOpenInstallLink(link, ota: ota))
        await gate.release(); await installation.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path)); XCTAssertNil(model.readyLink)
        XCTAssertNil(ota.activeSession)
    }
    func testSavedInstallMarksItsShelfRowWhileItRuns() async throws {
        let entry = try await signedInstallEntry(), model = try signingModel()
        let entered = expectation(description: "phone delivery"), gate = ShelfInstallGate(), publisher = ShelfCapturePublisher()
        let ota = OTAInstallModel(store: ShelfInstallSecrets(), bucketStore: ShelfInstallSecrets(), sweepOnStart: false,
            preparePhone: { _ in .init(publisher: publisher, wait: { _ in entered.fulfill(); await gate.wait(); return true }) })
        ota.hostKind = .phone; ota.certificateFeedText = "https://fixture.example/cert.json"
        XCTAssertNil(model.savedInstallID)
        let installation = Task { await model.installSaved(entry, ota: ota, open: { _ in }) }
        await fulfillment(of: [entered], timeout: 5)
        XCTAssertEqual(model.savedInstallID, entry.id)
        await gate.release(); await installation.value
        XCTAssertNil(model.savedInstallID)
    }
    func testSavedInstallCancelCannotPublishOverNewProbe() async throws {
        let entry = try await signedInstallEntry(), model = try signingModel()
        let entered = expectation(description: "upload readiness"), gate = ShelfInstallGate()
        let ota = OTAInstallModel(store: ShelfInstallSecrets(), bucketStore: ShelfInstallSecrets(), sweepOnStart: false,
            prepareServer: { _, _ in entered.fulfill(); await gate.wait(); return .init(publisher: ShelfInstallPublisher(check: { _ in XCTFail("canceled upload") })) })
        ota.hostKind = .server; ota.serverText = "https://fixture.example"
        let installation = Task { await model.installSaved(entry, ota: ota, open: { _ in XCTFail("canceled link") }) }
        await fulfillment(of: [entered], timeout: 5)
        model.cancelInstallation(ota: ota)
        let probe = try ota.reserve()
        await gate.release(); await installation.value
        XCTAssertTrue(ota.owns(probe)); XCTAssertFalse(model.installing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: entry).path)); ota.release(probe)
    }
    func testSavedInstallBlocksStrangerUsingRunningWaxID() async throws {
        let entry = try await signedInstallEntry(), tree = base.appendingPathComponent("clash-tree")
        try IPAExtractor.extract(ipa: library.url(for: entry), to: tree)
        let info = try IPAInspector.inspect(url: library.url(for: entry))
        let plist = tree.appendingPathComponent("Payload/" + info.appFolder + "/Info.plist")
        var dict = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        dict["CFBundleIdentifier"] = Bundle.main.bundleIdentifier!
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: plist)
        let file = base.appendingPathComponent("clash.ipa"); try IPAArchiver.archive(directory: tree, to: file)
        let clash = try await library.fileNow(file, info: IPAInspector.inspect(url: file), signed: true).entry
        let model = try signingModel(), ota = installer { _ in XCTFail("a different executable cannot replace Wax") }
        await model.installSaved(clash, ota: ota, open: { _ in XCTFail() })
        XCTAssertTrue(model.savedInstallError?.contains("replace Wax") == true)
    }
    func testSavedInstallDeliveryFailureIsVisibleOnShelfAndRemovesSnapshot() async throws {
        let entry = try await signedInstallEntry(), model = try signingModel(), publisher = ShelfCapturePublisher()
        let ota = OTAInstallModel(store: ShelfInstallSecrets(), bucketStore: ShelfInstallSecrets(), sweepOnStart: false,
            preparePhone: { _ in .init(publisher: publisher, wait: { _ in false }) })
        ota.hostKind = .phone; ota.certificateFeedText = "https://fixture.example/cert.json"
        await model.installSaved(entry, ota: ota, open: { _ in })
        let captured = await publisher.path(), snapshot = try XCTUnwrap(captured)
        XCTAssertNotNil(model.savedInstallError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path)); XCTAssertNil(model.readyLink)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: entry).path))
    }
    func testSavedInstallRejectsWrongMetadataAndAllowsRecoveredSignedEntry() async throws {
        let entry = try await signedInstallEntry()
        let file = library.url(for: entry), info = try IPAInspector.inspect(url: file)
        let wrongStorage = IPALibrary(root: base.appendingPathComponent("mismatch"))
        let wrong = try wrongStorage.save(file: file, kind: .signed, name: info.displayName, version: "wrong-version", bundleID: info.bundleIdentifier).entry
        let wrongLibrary = LibraryModel(library: wrongStorage, load: false)
        let model = SigningModel(credentials: CredentialsModel(store: try CredentialStore(directory: base.appendingPathComponent("mismatch-creds"))), library: wrongLibrary)
        let blocked = installer { _ in XCTFail("mismatched metadata published") }
        await model.installSaved(wrong, ota: blocked, open: { _ in XCTFail() })
        XCTAssertNotNil(model.savedInstallError)
        let recoveredRoot = base.appendingPathComponent("recovered"), folder = recoveredRoot.appendingPathComponent("signed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent("orphan.ipa"))
        let storage = IPALibrary(root: recoveredRoot); try storage.repairIndex()
        let recovered = try XCTUnwrap(storage.entries(.signed).first)
        let recoveredLibrary = LibraryModel(library: storage, load: false)
        let recoveredModel = SigningModel(credentials: CredentialsModel(store: try CredentialStore(directory: base.appendingPathComponent("recovered-creds"))), library: recoveredLibrary)
        let uploaded = expectation(description: "recovered signed bytes")
        let ota = installer { _ in uploaded.fulfill() }
        await recoveredModel.installSaved(recovered, ota: ota, open: { _ in })
        await fulfillment(of: [uploaded], timeout: 2); XCTAssertNil(recoveredModel.savedInstallError)
    }
    func testManualImportAnnouncesOnlyAfterCommitAndUsesUnsignedShelf() async throws {
        let result = try await library.importPicked(pickedCopy())
        XCTAssertTrue(library.saveState.confirmedSaved); XCTAssertEqual(result.entry.kind, .unsigned)
        XCTAssertEqual(result.entry.provenance, .fileImport); XCTAssertEqual(announcements.count, 1)
        XCTAssertTrue(announcements[0].hasPrefix("Added")); XCTAssertFalse(library.unsigned.isEmpty)
    }
    func testImportSaveFailurePreservesDurableArtifactAndNeverAnnouncesAdded() async throws {
        try blockIndex()
        let error = await failure { _ = try await self.library.importPicked(self.pickedCopy()) }
        let retained = try XCTUnwrap(error?.artifact)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path)); XCTAssertTrue(announcements.isEmpty)
        XCTAssertFalse(library.saveState.confirmedSaved); XCTAssertTrue(library.unsigned.isEmpty)
        XCTAssertTrue(error?.localizedDescription.contains("Retry") == true)
        XCTAssertNotNil(try? IPAInspector.inspect(url: retained))
    }
    func testRetryCommitSucceedsWithoutOriginalPickerFile() async throws {
        try blockIndex()
        let error = await failure { _ = try await self.library.importPicked(self.pickedCopy()) }
        let id = try XCTUnwrap(error?.pendingID)
        try unblockIndex()
        let saved = try await library.retryImport(id)
        XCTAssertEqual(announcements.count, 1)
        XCTAssertTrue(library.saveState.confirmedSaved); XCTAssertEqual(library.unsigned.count, 1)
        XCTAssertNotNil(try? IPAInspector.inspect(url: library.url(for: saved.entry)))
    }
    func testRepeatedRetryFailureKeepsExportableBytes() async throws {
        try blockIndex()
        let error = await failure { _ = try await self.library.importPicked(self.pickedCopy()) }
        let id = try XCTUnwrap(error?.pendingID), artifact = try XCTUnwrap(error?.artifact), before = try Data(contentsOf: artifact)
        _ = await failure { _ = try await self.library.finishPending(id) }
        let exported = base.appendingPathComponent("export.ipa"); try FileManager.default.copyItem(at: artifact, to: exported)
        XCTAssertEqual(try Data(contentsOf: exported), before); XCTAssertFalse(library.saveState.confirmedSaved)
    }
    func testDownloadSaveFailureDoesNotFileRouteAnnounceOrRedownloadOnRetry() async throws {
        try blockIndex()
        var downloads = 0, spoken: [String] = []
        let model = SourcesModel(sourceStore: SourceStore(directory: base.appendingPathComponent("sources")), download: { _, directory in
            downloads += 1
            let file = directory.appendingPathComponent("download.ipa")
            try FileManager.default.copyItem(at: self.fixture, to: file); return file
        }, announce: { spoken.append($0) })
        let app = SourceApp(id: "test", name: "Demo", bundleID: "com.demo", version: "1", size: nil, iconURL: nil,
                            downloadURL: URL(string: "https://example.invalid/test.ipa")!, date: nil, summary: "", developer: "")
        let signing = try signingModel(), router = Router(); router.tab = .sources
        await model.get(app, from: nil, signAfter: true, library: library, signing: signing, router: router)?.value
        XCTAssertFalse(model.isFiled(app, source: nil, library: library)); XCTAssertTrue(spoken.isEmpty); XCTAssertEqual(router.tab, .sources)
        let retained = try XCTUnwrap(model.retainedFile(app, source: nil)); XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertNotNil(model.message); XCTAssertEqual(downloads, 1)
        let pendingBefore = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("pending").path)
        await model.get(app, from: nil, signAfter: false, library: library, signing: signing, router: router)?.value
        XCTAssertEqual(downloads, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("pending").path), pendingBefore)
        try unblockIndex()
        await model.get(app, from: nil, signAfter: false, library: library, signing: signing, router: router)?.value
        XCTAssertEqual(downloads, 1); XCTAssertTrue(model.isFiled(app, source: nil, library: library)); XCTAssertEqual(spoken.count, 1)
        XCTAssertNil(model.retainedFile(app, source: nil)); XCTAssertEqual(library.unsigned.count, 1)
        XCTAssertEqual(library.unsigned.first?.provenance, .sourceDownload)
    }
    func testExpiredNoncooperativeDownloadIsRetainedAndRetrySavesWithoutRedownload() async throws {
        var expiration: (@MainActor () -> Void)?, resume: CheckedContinuation<Void, Never>?
        let entered = expectation(description: "download entered")
        let background = BackgroundJob(system: .init(beginGrace: { _, expired in expiration = expired; return UIBackgroundTaskIdentifier(rawValue: 1) },
            endGrace: { _ in }, requestContinued: { _ in }, cancelContinued: {}, isInBackground: { true }))
        var downloads = 0, spoken: [String] = []
        let model = SourcesModel(sourceStore: SourceStore(directory: base.appendingPathComponent("sources")), download: { _, directory in
            downloads += 1
            let file = directory.appendingPathComponent("completed.ipa")
            try FileManager.default.copyItem(at: self.fixture, to: file)
            await withCheckedContinuation { resume = $0; entered.fulfill() }
            return file // deliberately returns useful bytes despite cancellation
        }, announce: { spoken.append($0) }, background: background)
        let app = SourceApp(id: "test", name: "Demo", bundleID: "com.demo", version: "1", size: nil, iconURL: nil,
            downloadURL: URL(string: "https://fixture.invalid/app.ipa")!, date: nil, summary: "", developer: "")
        let signing = try signingModel(), router = Router(); router.tab = .sources
        let task = try XCTUnwrap(model.get(app, from: nil, signAfter: true, library: library, signing: signing, router: router))
        await fulfillment(of: [entered], timeout: 5); expiration?(); resume?.resume(); await task.value
        XCTAssertFalse(model.isFiled(app, source: nil, library: library)); XCTAssertTrue(spoken.isEmpty)
        XCTAssertEqual(router.tab, .sources); XCTAssertEqual(background.activeCount, 0)
        let retained = try XCTUnwrap(model.retainedFile(app, source: nil)); XCTAssertNotNil(try? IPAInspector.inspect(url: retained))
        XCTAssertTrue(model.message?.contains("kept") == true)
        await model.get(app, from: nil, signAfter: false, library: library, signing: signing, router: router)?.value
        XCTAssertEqual(downloads, 1); XCTAssertTrue(model.isFiled(app, source: nil, library: library)); XCTAssertEqual(spoken.count, 1)
        XCTAssertNil(model.retainedFile(app, source: nil))
    }
    func testImmediateBackgroundExpirationCancelsDownloadBeforeItStarts() async throws {
        let background = BackgroundJob(system: .init(beginGrace: { _, expired in expired(); return UIBackgroundTaskIdentifier(rawValue: 1) },
            endGrace: { _ in }, requestContinued: { _ in }, cancelContinued: {}, isInBackground: { true }))
        let model = SourcesModel(sourceStore: SourceStore(directory: base.appendingPathComponent("sources")), download: { _, _ in XCTFail("canceled before start"); throw CancellationError() },
            announce: { _ in XCTFail("cannot announce success") }, background: background)
        let app = SourceApp(id: "test", name: "Demo", bundleID: "com.demo", version: "1", size: nil, iconURL: nil,
            downloadURL: URL(string: "https://fixture.invalid/app.ipa")!, date: nil, summary: "", developer: "")
        await model.get(app, from: nil, signAfter: false, library: library, signing: try signingModel(), router: Router())?.value
        XCTAssertFalse(model.isFiled(app, source: nil, library: library)); XCTAssertEqual(background.activeCount, 0)
    }
    private func signedPendingAndReport() throws -> (UUID, SigningModel.Report) {
        let pending = try library.storage.reserve(kind: .signed, name: "Signed test", provenance: .waxSigned)
        let output = try library.storage.pendingURL(pending.id); try FileManager.default.copyItem(at: fixture, to: output)
        let info = try IPAInspector.inspect(url: output)
        let report = SigningModel.Report(archiveLines: ["Engine result"], checkSummary: "Passed consistency checks", checkFailures: [], profileLines: [], warnings: [],
            output: output, outputSize: (try Data(contentsOf: output)).count,
            installTarget: InstallTarget(ipa: output, bundleIdentifier: info.bundleIdentifier, version: info.version, build: info.build, title: info.displayName))
        // This tests the app's post-engine persistence state, not cryptographic signing. SigningKit owns engine tests.
        return (pending.id, report)
    }
    func testSigningSuccessWithSaveFailureKeepsReportExportAndRetry() async throws {
        try blockIndex()
        let model = try signingModel(), (id, result) = try signedPendingAndReport()
        await model.acceptSignedResult(result, pendingID: id)
        XCTAssertNotNil(model.report); XCTAssertEqual(model.report?.checkSummary, result.checkSummary)
        XCTAssertFalse(model.shelfSaveState.confirmedSaved)
        let retained = try XCTUnwrap(model.report?.output); XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        let export = base.appendingPathComponent("signed-export.ipa"); try FileManager.default.copyItem(at: retained, to: export)
        XCTAssertEqual(try Data(contentsOf: retained), try Data(contentsOf: export))
        await model.retrySignedSave(); XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        try unblockIndex(); await model.retrySignedSave()
        XCTAssertTrue(model.shelfSaveState.confirmedSaved); XCTAssertEqual(library.signed.count, 1)
        XCTAssertEqual(model.report?.output, library.signed.first.map { library.url(for: $0) })
        XCTAssertEqual(model.report?.installTarget.ipa, model.report?.output)
    }
    func testStartingOverDoesNotDeleteUnsavedSignedArtifact() async throws {
        try blockIndex()
        let model = try signingModel(), (id, result) = try signedPendingAndReport()
        await model.acceptSignedResult(result, pendingID: id)
        let file = try XCTUnwrap(model.report?.output)
        model.clearResult()
        XCTAssertNil(model.report); XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let (_, next) = try signedPendingAndReport(); XCTAssertNotEqual(next.output, file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testRestartExposesFailedSignedArtifactForRecovery() async throws {
        try blockIndex()
        let model = try signingModel(), (id, result) = try signedPendingAndReport()
        await model.acceptSignedResult(result, pendingID: id)
        let restarted = LibraryModel(library: IPALibrary(root: root), load: false)
        await restarted.refresh()
        XCTAssertEqual(restarted.recovery.count, 1); XCTAssertNotNil(try? IPAInspector.inspect(url: restarted.recovery[0].url))
    }
    func testExactDuplicateReturnsAlreadySavedState() async throws {
        let info = try IPAInspector.inspect(url: fixture)
        let first = try await library.fileNow(fixture, info: info)
        let duplicate = try await library.fileNow(fixture, info: info)
        XCTAssertEqual(first.entry.id, duplicate.entry.id); XCTAssertTrue(duplicate.alreadySaved)
        XCTAssertTrue(library.saveState.confirmedSaved)
    }
    func testDeleteAndClearIndexFailuresAreSurfacedWithoutDroppingVisibleFiles() async throws {
        let saved = try await library.importPicked(pickedCopy())
        let index = root.appendingPathComponent("index.json"), before = try Data(contentsOf: index)
        try FileManager.default.removeItem(at: index); try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        await library.remove(saved.entry)
        XCTAssertNotNil(library.message); XCTAssertEqual(library.unsigned.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.url(for: saved.entry).path))
        await library.clear(.unsigned)
        XCTAssertEqual(library.unsigned.count, 1)
        XCTAssertTrue(announcements.contains { !$0.hasPrefix("Added") && !$0.hasPrefix("Already saved") })
        try FileManager.default.removeItem(at: index); try before.write(to: index)
    }

    func testSignatureMarkerDoesNotClassifyADownloadAsWaxSigned() async throws {
        let tree = base.appendingPathComponent("publisher-tree")
        try IPAExtractor.extract(ipa: fixture, to: tree)
        let input = try IPAInspector.inspect(url: fixture)
        let resources = tree.appendingPathComponent("Payload/" + input.appFolder + "/_CodeSignature")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data("synthetic signature marker, not a valid signature".utf8).write(to: resources.appendingPathComponent("CodeResources"))
        let marked = base.appendingPathComponent("marked.ipa"); try IPAArchiver.archive(directory: tree, to: marked)
        let info = try IPAInspector.inspect(url: marked); XCTAssertTrue(info.hasCodeSignature)
        let saved = try await library.fileNow(marked, info: info, provenance: .sourceDownload)
        XCTAssertEqual(saved.entry.kind, .unsigned); XCTAssertEqual(saved.entry.provenance, .sourceDownload)
        XCTAssertTrue(library.signed.isEmpty)
    }

    func testRetryAfterAnotherRecoveryCommittedStillReturnsUsableEntry() async throws {
        try blockIndex()
        let error = await failure { _ = try await self.library.importPicked(self.pickedCopy()) }
        let id = try XCTUnwrap(error?.pendingID)
        try unblockIndex()
        _ = try library.storage.commit(id)
        let result = try await library.finishPending(id)
        XCTAssertTrue(result.alreadySaved); XCTAssertTrue(library.saveState.confirmedSaved)
        XCTAssertNotNil(try? IPAInspector.inspect(url: library.url(for: result.entry)))
    }

    func testSameAppIDAcrossSourcesNeverReusesAnotherRetainedArtifact() async throws {
        let tree = base.appendingPathComponent("variant-tree")
        try IPAExtractor.extract(ipa: fixture, to: tree)
        let original = try IPAInspector.inspect(url: fixture)
        let plist = tree.appendingPathComponent("Payload/" + original.appFolder + "/Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        info["CFBundleVersion"] = "456"
        try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: plist)
        let variant = base.appendingPathComponent("variant.ipa"); try IPAArchiver.archive(directory: tree, to: variant)
        try blockIndex()
        let firstSource = UUID(), secondSource = UUID()
        var downloads = 0
        let model = SourcesModel(sourceStore: SourceStore(directory: base.appendingPathComponent("sources")), download: { app, directory in
            downloads += 1
            let file = directory.appendingPathComponent("download.ipa")
            try FileManager.default.copyItem(at: app.downloadURL.lastPathComponent == "b.ipa" ? variant : self.fixture, to: file)
            return file
        }, announce: { _ in })
        func app(_ path: String) -> SourceApp {
            SourceApp(id: "same-app@1", name: "Same app", bundleID: original.bundleIdentifier, version: "1", size: nil,
                iconURL: nil, downloadURL: URL(string: "https://example.invalid/" + path)!, date: nil, summary: "", developer: "")
        }
        let a = app("a.ipa"), b = app("b.ipa"), signing = try signingModel(), router = Router()
        await model.get(a, from: firstSource, signAfter: false, library: library, signing: signing, router: router)?.value
        await model.get(b, from: secondSource, signAfter: false, library: library, signing: signing, router: router)?.value
        XCTAssertEqual(downloads, 2)
        XCTAssertNotEqual(model.retainedFile(a, source: firstSource), model.retainedFile(b, source: secondSource))
        try unblockIndex()
        await model.get(b, from: secondSource, signAfter: false, library: library, signing: signing, router: router)?.value
        XCTAssertEqual(downloads, 2); XCTAssertEqual(library.unsigned.first?.build, "456")
        XCTAssertTrue(model.isFiled(b, source: secondSource, library: library))
        XCTAssertFalse(model.isFiled(a, source: firstSource, library: library))
        await model.get(a, from: firstSource, signAfter: false, library: library, signing: signing, router: router)?.value
        XCTAssertEqual(library.unsigned.count, 2)
        XCTAssertTrue(library.recovery.isEmpty, "successful cleanup must remove stale recovery rows")
        let savedB = try XCTUnwrap(library.unsigned.first { $0.build == "456" })
        await library.remove(savedB)
        XCTAssertFalse(model.isFiled(b, source: secondSource, library: library))
        XCTAssertTrue(model.isFiled(a, source: firstSource, library: library))
    }

}

private struct ShelfInstallSecrets: SecretStore {
    func load() -> Data? { Data(String(repeating: "t", count: 40).utf8) }
    func save(_ data: Data) throws {}
    func delete() {}
}
private struct ShelfInstallPublisher: InstallHost {
    let check: @Sendable (URL) throws -> Void
    func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try check(ipa); progress(1)
        return URL(string: "itms-services://?action=download-manifest&url=https://fixture.example/manifest")!
    }
}

private actor ShelfInstallGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async { if !opened { await withCheckedContinuation { waiter = $0 } } }
    func release() { opened = true; waiter?.resume(); waiter = nil }
}
private actor ShelfCapturePublisher: InstallHost {
    private var captured: URL?
    func path() -> URL? { captured }
    func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        captured = ipa
        return URL(string: "itms-services://?action=download-manifest&url=https://fixture.example/manifest")!
    }
}
