import CredentialKit
import IPAKit
import XCTest
@testable import SigningKit

final class PreparedIPATests: XCTestCase {
    private var root: URL!
    private var input: URL!
    private var credentials: TestCredentials!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("prepared-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        input = root.appendingPathComponent("input.ipa")
        try FileManager.default.copyItem(at: Fixtures.ipa, to: input)
        credentials = try TestCredentials()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private var output: URL { root.appendingPathComponent("output.ipa") }
    private func prepare(edits: AppEdits = .init(), options: SigningOptions = .init(),
                         limits: PreparedIPA.Limits = .init(), profiles: ProfileSet? = nil,
                         policy: SigningPlan.ProfilePolicy = .requireValidCMS,
                         progress: ((SigningProgress) -> Void)? = nil) throws -> PreparedIPA {
        try PreparedIPA.prepare(ipa: input, certificateChainDER: credentials.signer.certificateChainDER,
            certificateTeamID: credentials.loaded.teamID, profiles: profiles ?? ProfileSet(single: .parse(FixtureData.profileWildcardAll)),
            options: options, edits: edits, workDirectory: root, limits: limits, profilePolicy: policy, progress: progress)
    }
    private func unpack(_ file: URL) throws -> URL {
        let tree = root.appendingPathComponent("check-\(UUID())")
        try IPAExtractor.extract(ipa: file, to: tree)
        return tree.appendingPathComponent("Payload/" + (try IPAInspector.inspect(url: file)).appFolder)
    }
    func testPreparationFreezesActualRandomizationIdentityAndVersionBuildOnce() throws {
        var edits = AppEdits(); edits.randomizeBundleID = true; edits.version = "9.1"; edits.build = "42"; edits.displayName = "Prepared"
        let lease = try prepare(edits: edits), preview = lease.preview
        XCTAssertNotEqual(preview.original.identifier, preview.proposed.identifier)
        XCTAssertEqual(preview.proposed.version, "9.1"); XCTAssertEqual(preview.proposed.build, "42")
        let outcome = try lease.execute(identity: credentials.signer, output: output)
        XCTAssertEqual(outcome.outputArchive.bundleIdentifier, preview.proposed.identifier)
        XCTAssertEqual(outcome.outputArchive.displayName, "Prepared")
        XCTAssertEqual(outcome.outputArchive.version, "9.1"); XCTAssertEqual(outcome.outputArchive.build, "42")
        XCTAssertEqual(outcome.signing.profileSelections, preview.bundles.map(\.profile))
        XCTAssertTrue(outcome.selfCheck.passed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.work.path))
        let app = try unpack(output)
        for bundle in preview.bundles {
            let signed = try XCTUnwrap(outcome.signing.items.first { $0.relativePath == bundle.path })
            XCTAssertEqual(signed.identifier, bundle.identifier)
            let actual = try MachO(Data(contentsOf: app.appendingPathComponent(bundle.path == "." ? "SigningTestApp" : "PlugIns/TestExt.appex/TestExt")))
            let expected = try PropertyListSerialization.propertyList(from: bundle.signedEntitlementsXML, format: nil) as! NSDictionary
            // Read the final executable's signed XML, not just the result's key list.
            let signature = try XCTUnwrap(actual.existingSignature)
            let entitlements = try XCTUnwrap(BlobReader.entitlements(inSignature: actual.data.subdata(in: signature.offset..<(signature.offset + signature.size))))
            XCTAssertEqual(entitlements as NSDictionary, expected)
        }
    }
    func testReadOnlyPreviewIncludesFrameworkAndExtensionAndUnknownTrust() throws {
        let original = try Data(contentsOf: input), lease = try prepare()
        defer { lease.discard() }
        XCTAssertEqual(try Data(contentsOf: input), original)
        XCTAssertEqual(lease.preview.code.map(\.kind).sorted(), ["app", "appex", "framework"])
        XCTAssertEqual(Set(lease.preview.code.map(\.path)), [".", "Frameworks/TestKit.framework", "PlugIns/TestExt.appex"])
        XCTAssertTrue(lease.preview.bundles.allSatisfy {
            if case .signatureValidButUntrusted = $0.profile.signatureStatus { return true }; return false
        })
        XCTAssertTrue(lease.preview.installationAssessment.contains("Not determined"))
        XCTAssertEqual(lease.preview.sourceSHA256.count, 64)
    }
    func testSourceChangedAfterPreviewRejectsAndPreservesExistingOutput() throws {
        let lease = try prepare(), good = Data("earlier saved IPA".utf8)
        try good.write(to: output)
        var bytes = try Data(contentsOf: input); bytes[bytes.count - 1] ^= 1; try bytes.write(to: input)
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .sourceChanged) }
        XCTAssertEqual(try Data(contentsOf: output), good)
    }
    func testMissingSourceRejectsWithoutOutput() throws {
        let lease = try prepare(); try FileManager.default.removeItem(at: input)
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testTamperedPreparedTreeIncludingOutsideMainAppIsRejected() throws {
        for path in ["Payload/extra", "Payload/SigningTestApp.app/note.txt", "Payload/SigningTestApp.app/SigningTestApp"] {
            let lease = try prepare()
            try Data("tampered".utf8).write(to: lease.tree.appendingPathComponent(path))
            XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) {
                guard case IPAError.integrity = $0 else { return XCTFail("expected integrity error: \($0)") }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }
    func testConfirmationIsOnceOnlyAndDiscardDoesNotDeleteCompletedOutput() throws {
        let lease = try prepare()
        _ = try lease.execute(identity: credentials.signer, output: output)
        let bytes = try Data(contentsOf: output)
        lease.discard()
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .consumed) }
        XCTAssertEqual(try Data(contentsOf: output), bytes)
    }
    func testCancellationDuringPreparationRemovesOnlyOwnedScratch() throws {
        let token = SigningCancellation(); var options = SigningOptions(); options.cancellation = token
        let existing = root.appendingPathComponent("unrelated"); try Data([7]).write(to: existing)
        XCTAssertThrowsError(try prepare(options: options, progress: { if $0.message == "Preparing the IPA…" { token.cancel() } })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data([7]))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("prepared-") })
    }
    func testCancellationAfterPreviewPreventsPrivateKeyUse() throws {
        let lease = try prepare(); lease.cancellation.cancel()
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testCancellationDuringSigningAndPackingPreservesOldOutput() throws {
        for stage in ["Signing confirmed plan…", "Packing…"] {
            let lease = try prepare(), old = Data("old IPA".utf8); try old.write(to: output)
            XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output, progress: { if $0.message == stage { lease.cancellation.cancel() } })) {
                XCTAssertTrue($0 is CancellationError)
            }
            XCTAssertEqual(try Data(contentsOf: output), old)
        }
    }
    func testDiscardReleasesScratchAndRefusesConfirmation() throws {
        let lease = try prepare(); lease.discard(); lease.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.work.path))
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .consumed) }
        XCTAssertNotNil(try? IPAInspector.inspect(url: input))
    }
    func testExpiredPreparationIsRejectedWithoutLeakingScratch() throws {
        var limits = PreparedIPA.Limits(); limits.lifetime = 0.000000001
        XCTAssertThrowsError(try prepare(limits: limits)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .expired) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("prepared-") })
    }
    func testScratchAndCodeBudgetsRejectWithoutOutput() throws {
        var limits = PreparedIPA.Limits(); limits.maximumPreparedBytes = 1
        XCTAssertThrowsError(try prepare(limits: limits))
        limits = .init(); limits.maximumCodeFileBytes = 4
        XCTAssertThrowsError(try prepare(limits: limits)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .codeLimit) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testPackagingBudgetAndLowStorageFailuresPreserveOutput() throws {
        for disk in [false, true] {
            var limits = PreparedIPA.Limits()
            if disk { limits.packaging.minimumFreeBytes = Int64.max } else { limits.packaging.maximumTemporaryBytes = 1 }
            let lease = try prepare(limits: limits), old = Data([9]); try old.write(to: output)
            XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) {
                XCTAssertTrue($0 is IPAArchiver.BudgetError)
            }
            XCTAssertEqual(try Data(contentsOf: output), old)
        }
    }
    func testExtractionLowStorageRefusesAndCleansUp() throws {
        var limits = PreparedIPA.Limits(); limits.extraction.minimumFreeBytes = Int64.max
        XCTAssertThrowsError(try prepare(limits: limits)) { XCTAssertTrue($0 is IPAExtractor.BudgetError) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("prepared-") })
    }
    func testUnknownAndIncompatibleOverridesAreRejected() throws {
        let profile = try ProvisioningProfile.parse(FixtureData.profileExactTestExt)
        for path in ["missing.appex", "."] {
            XCTAssertThrowsError(try prepare(profiles: ProfileSet(pool: [.parse(FixtureData.profileWildcardAll)], overrides: [path: profile])))
        }
    }
    func testNestedOverrideUsesTheChosenProfileAndFrozenBytes() throws {
        let nested = try ProvisioningProfile.parse(FixtureData.profileExactTestExt)
        let profiles = try ProfileSet(pool: [.parse(FixtureData.profileWildcardAll)], overrides: ["PlugIns/TestExt.appex": nested])
        let lease = try prepare(profiles: profiles)
        XCTAssertEqual(lease.preview.bundles.first { $0.path == "PlugIns/TestExt.appex" }?.profile.profileID, nested.info.id)
        let outcome = try lease.execute(identity: credentials.signer, output: output)
        let app = try unpack(outcome.output)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("PlugIns/TestExt.appex/embedded.mobileprovision")), nested.rawData)
    }
    func testUnauthorizedEntitlementsAreVisibleOrStrictlyRefused() throws {
        var options = SigningOptions(); options.overrideEntitlements = ["ungranted.fixture": true]
        let lease = try prepare(options: options); defer { lease.discard() }
        XCTAssertEqual(lease.preview.bundles[0].entitlements.first { $0.key == "ungranted.fixture" }?.disposition, .dropped)
        options.entitlementPolicy = .reject
        XCTAssertThrowsError(try prepare(options: options)) { XCTAssertTrue($0.localizedDescription.contains("does not grant")) }
    }
    func testInvalidCMSIsRefusedInProductionButExplicitFixturePolicyRemains() throws {
        let cms = try CMSSignedData.parse(FixtureData.profileWildcardAll)
        let content = try XCTUnwrap(cms.encapsulatedContent)
        let unsigned = DER.sequence([DER.oid("1.2.840.113549.1.7.2"), DER.tlv(0xa0, DER.sequence([
            DER.integer(1), DER.setOf([]), DER.sequence([DER.oid("1.2.840.113549.1.7.1"), DER.tlv(0xa0, DER.octetString(content))]), DER.setOf([])
        ]))])
        let profiles = try ProfileSet(single: .parse(unsigned))
        XCTAssertThrowsError(try prepare(profiles: profiles)) { XCTAssertTrue($0.localizedDescription.contains("CMS signature invalid")) }
        let lease = try prepare(profiles: profiles, policy: .allowInvalidForTesting); defer { lease.discard() }
        guard case .invalid = lease.preview.bundles[0].profile.signatureStatus else { return XCTFail("fixture cannot promote trust") }
    }
    func testDifferentIdentityRefusedAndOptionsCannotChangeFrozenDecision() throws {
        struct Wrong: CodeSigningIdentity {
            var certificateChainDER: [Data] { [Data([0])] }
            func signRSAPKCS1SHA256(_ message: Data) throws -> Data { XCTFail("no private key call"); return Data() }
        }
        var options = SigningOptions(); options.overrideEntitlements = ["unknown.old": true]
        let lease = try prepare(options: options)
        options.overrideEntitlements = ["different.new": true]
        XCTAssertTrue(lease.preview.bundles[0].entitlements.contains { $0.key == "unknown.old" })
        XCTAssertFalse(lease.preview.bundles[0].entitlements.contains { $0.key == "different.new" })
        XCTAssertThrowsError(try lease.execute(identity: Wrong(), output: output)) { XCTAssertTrue($0.localizedDescription.contains("chain changed")) }
    }
    func testOutputCannotBePlacedInsideDisposableScratchOrReplaceInput() throws {
        for inside in [true, false] {
            let lease = try prepare(), original = try Data(contentsOf: input)
            XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: inside ? lease.work.appendingPathComponent("output.ipa") : input))
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }
    func testFinalGateRejectsMutationAfterSignatureCheck() throws {
        let lease = try prepare(), old = Data([8]); try old.write(to: output)
        var changed = false
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output, progress: { p in
            guard p.message == "Packing…", !changed else { return }; changed = true
            try! Data("corrupt".utf8).write(to: lease.tree.appendingPathComponent("Payload/SigningTestApp.app/_CodeSignature/CodeResources"))
        })) { guard case IPAError.integrity = $0 else { return XCTFail("expected integrity refusal: \($0)") } }
        XCTAssertTrue(changed); XCTAssertEqual(try Data(contentsOf: output), old)
    }
    func testImportedLibraryBytesAreFrozenAndDoNotRequireSourceAtConfirmation() throws {
        let library = root.appendingPathComponent("Hook.dylib")
        try FileManager.default.copyItem(at: Fixtures.appDirectory.appendingPathComponent("Frameworks/TestKit.framework/TestKit"), to: library)
        var edits = AppEdits(); edits.injectLibraries = [library]
        let lease = try prepare(edits: edits)
        XCTAssertTrue(lease.preview.changes.contains { $0.contains("Hook.dylib") })
        XCTAssertTrue(lease.preview.code.contains { $0.path == "Frameworks/Hook.dylib" })
        try FileManager.default.removeItem(at: library)
        let outcome = try lease.execute(identity: credentials.signer, output: output)
        XCTAssertTrue(outcome.selfCheck.passed)
        let app = try unpack(outcome.output)
        XCTAssertTrue(try MachO(Data(contentsOf: app.appendingPathComponent("SigningTestApp"))).loadDylibNames.contains { $0.hasSuffix("Hook.dylib") })
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).passed)
    }
    func testCancellationInsideActualPrivateKeyOperationPreventsPublication() throws {
        struct Canceling: CodeSigningIdentity {
            let base: SecurityFrameworkIdentity
            let owner: SigningCancellation
            var certificateChainDER: [Data] { base.certificateChainDER }
            func signRSAPKCS1SHA256(_ message: Data) throws -> Data {
                let signed = try base.signRSAPKCS1SHA256(message)
                owner.cancel(); return signed
            }
        }
        let lease = try prepare(), old = Data([1, 9]); try old.write(to: output)
        XCTAssertThrowsError(try lease.execute(identity: Canceling(base: credentials.signer, owner: lease.cancellation), output: output)) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: output), old)
    }
    func testCancellationAtLastPackingProgressPreservesExistingArtifact() throws {
        let lease = try prepare(), old = Data([2, 8]); try old.write(to: output)
        var reached = false
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output, progress: { p in
            if p.message == "Packing…", p.fraction > 0.99 { reached = true; lease.cancellation.cancel() }
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertTrue(reached); XCTAssertEqual(try Data(contentsOf: output), old)
    }
    func testPreviewExpirationAndClockRollbackRejectBeforeSigning() throws {
        final class Clock: @unchecked Sendable {
            let lock = NSLock(); var value: UInt64 = 10
            func now() -> UInt64 { lock.withLock { value } }
            func set(_ next: UInt64) { lock.withLock { value = next } }
        }
        for rollback in [false, true] {
            let clock = Clock(); var limits = PreparedIPA.Limits()
            limits.lifetime = 1; limits.uptime = { clock.now() }
            let lease = try prepare(limits: limits)
            clock.set(rollback ? 9 : 1_000_000_010)
            XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .expired) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: lease.work.path))
        }
    }
    func testConcurrentConfirmationCannotDeleteOrExecuteAnotherOwnersScratch() throws {
        let lease = try prepare(), entered = expectation(description: "execution owns scratch"), finished = expectation(description: "execution settled")
        let resume = DispatchSemaphore(value: 0), identity = credentials.signer
        DispatchQueue.global().async {
            do {
                _ = try lease.execute(identity: identity, output: self.output, progress: { p in
                    if p.message == "Signing confirmed plan…" {
                        entered.fulfill()
                        XCTAssertEqual(resume.wait(timeout: .now() + 5), .success)
                    }
                })
                XCTFail("discard must request cancellation")
            } catch { XCTAssertTrue(error is CancellationError) }
            finished.fulfill()
        }
        wait(for: [entered], timeout: 5)
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .consumed) }
        lease.discard()
        XCTAssertTrue(FileManager.default.fileExists(atPath: lease.work.path), "discard cannot remove executing scratch")
        resume.signal(); wait(for: [finished], timeout: 5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lease.work.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testPathReplacementCannotSwitchTheCapturedIPAOrItsPreviewIdentity() throws {
        let original = try Data(contentsOf: input)
        var replaced = false, restored = false
        let lease = try prepare(progress: { p in
            if p.message == "Preparing captured IPA…", !replaced {
                try! Data("a different file at the source path".utf8).write(to: self.input, options: .atomic)
                replaced = true
            } else if p.message == "Preparing the IPA…", replaced, !restored {
                try! original.write(to: self.input, options: .atomic); restored = true
            }
        })
        defer { lease.discard() }
        XCTAssertTrue(replaced); XCTAssertTrue(restored)
        XCTAssertEqual(lease.preview.original.identifier, try IPAInspector.inspect(url: Fixtures.ipa).bundleIdentifier)
        XCTAssertEqual(lease.preview.sourceSHA256, try PreparedIPA.fingerprint(input, checkpoint: {}))
        let outcome = try lease.execute(identity: credentials.signer, output: output)
        XCTAssertTrue(outcome.selfCheck.passed)
    }
    func testCapturedIPAMutationIsRefusedBeforeAnySigningOutput() throws {
        let lease = try prepare()
        let captured = lease.work.appendingPathComponent("source.ipa")
        var bytes = try Data(contentsOf: captured); bytes[bytes.count - 1] ^= 1; try bytes.write(to: captured)
        XCTAssertThrowsError(try lease.execute(identity: credentials.signer, output: output)) { XCTAssertEqual($0 as? PreparedIPA.Failure, .sourceChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testCapturedSourceAndExtractedTreeShareOneScratchLimit() throws {
        var limits = PreparedIPA.Limits(); limits.maximumPreparedBytes = try Data(contentsOf: input).count + 1
        XCTAssertThrowsError(try prepare(limits: limits))
        XCTAssertNotNil(try? IPAInspector.inspect(url: input))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("prepared-") })
    }
    #if os(macOS)
    func testPreparedRepackedOutputPassesIndependentAppleCodesign() throws {
        let lease = try prepare(); let start = DispatchTime.now().uptimeNanoseconds
        let outcome = try lease.execute(identity: credentials.signer, output: output)
        print("R15 fixture execute including self-check and R2 gate: \(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9) seconds")
        let app = try unpack(outcome.output)
        let result = Process.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(Process.run("/usr/bin/unzip", ["-tq", outcome.output.path]).status, 0)
    }
    #endif
}
