import XCTest
@testable import InstallKit

final class SignScreenLogicTests: XCTestCase {
    func testPhaseBusyBeatsErrorBeatsReport() {
        XCTAssertEqual(SignPhase.resolve(busy: true, hasError: true, hasReport: true), .signing)
        XCTAssertEqual(SignPhase.resolve(busy: false, hasError: true, hasReport: true), .failed)
        XCTAssertEqual(SignPhase.resolve(busy: false, hasError: false, hasReport: true), .done)
        XCTAssertEqual(SignPhase.resolve(busy: false, hasError: false, hasReport: false), .idle)
    }

    func testAFailedInstallTestHidesTheServerSetup() {
        XCTAssertEqual(InstallSetupPanel.resolve(testResult: .failed, setupComplete: true), .hidden)
    }

    func testAnUntestedIdentityShowsSetupWithAnUncertaintyNote() {
        XCTAssertEqual(InstallSetupPanel.resolve(testResult: nil, setupComplete: false), .show(collapsed: false, eligibilityUnknown: true))
        XCTAssertEqual(InstallSetupPanel.resolve(testResult: nil, setupComplete: true), .show(collapsed: true, eligibilityUnknown: true))
    }

    func testAVerifiedIdentityShowsSetupWithoutANote() {
        XCTAssertEqual(InstallSetupPanel.resolve(testResult: .installed, setupComplete: false), .show(collapsed: false, eligibilityUnknown: false))
        XCTAssertEqual(InstallSetupPanel.resolve(testResult: .installed, setupComplete: true), .show(collapsed: true, eligibilityUnknown: false))
    }
}

final class SignPrimaryTests: XCTestCase {
    private func resolve(hasApp: Bool = true, hasCertificates: Bool = true, chosen: Bool = true, installable: Bool = false,
                         server: Bool = true) -> SignPrimary {
        SignPrimary.resolve(hasApp: hasApp, hasCertificates: hasCertificates, certificateChosen: chosen,
                            inputIsInstallable: installable, serverReady: server)
    }

    func testNoAppAsksForOne() { XCTAssertEqual(resolve(hasApp: false), .needApp) }

    func testNoCertificatesAsksToImport() {
        XCTAssertEqual(resolve(hasCertificates: false, chosen: false), .needIdentity(canImport: true))
    }

    func testCertificatesButNoneChosenAsksToChoose() {
        XCTAssertEqual(resolve(chosen: false), .needIdentity(canImport: false))
    }

    // A dismissed install prompt counts as a failed test, so a failed test never blocks Sign & Install.
    func testAnyIdentityInstalls() { XCTAssertEqual(resolve(), .install) }

    func testMissingServerOffersSetup() { XCTAssertEqual(resolve(server: false), .needServer) }

    func testAlreadySignedInputCanInstallWithoutAnIdentity() {
        XCTAssertEqual(resolve(hasCertificates: false, chosen: false, installable: true), .install)
    }

    func testEveryStateHasWordsForTheButtonAndTheReason() {
        for p in [SignPrimary.needApp, .needIdentity(canImport: true), .needIdentity(canImport: false), .needServer, .install] {
            XCTAssertFalse(p.title.isEmpty); XCTAssertFalse(p.reason.isEmpty)
        }
    }
}

final class IdentityStatusTests: XCTestCase {
    private func facts(valid: Bool = true, compatible: Bool = true, expired: Bool = false, kind: IdentityFacts.ProfileKind = .adHoc,
                       test: InstallTestResult? = nil) -> IdentityFacts {
        IdentityFacts(certificateValid: valid, hasCompatibleProfile: compatible, profileExpired: expired, profileKind: kind, installTest: test)
    }

    func testAPairedValidUntestedIdentityIsReady() { XCTAssertEqual(IdentityStatus.evaluate(facts()), .ready) }

    func testDevelopmentAndEnterpriseProfilesAreNotJudgedByTheirType() {
        XCTAssertEqual(IdentityStatus.evaluate(facts(kind: .development)), .ready)
        XCTAssertEqual(IdentityStatus.evaluate(facts(kind: .enterprise)), .ready)
    }

    func testAnExpiredCertificateNeedsAttention() {
        guard case .needsAttention(let why) = IdentityStatus.evaluate(facts(valid: false)) else { return XCTFail() }
        XCTAssertTrue(why.localizedCaseInsensitiveContains("certificate"), why)
    }

    func testNoCompatibleProfileNeedsAttention() {
        guard case .needsAttention(let why) = IdentityStatus.evaluate(facts(compatible: false)) else { return XCTFail() }
        XCTAssertTrue(why.localizedCaseInsensitiveContains("profile"), why)
    }

    func testAnExpiredProfileNeedsAttention() {
        guard case .needsAttention = IdentityStatus.evaluate(facts(expired: true)) else { return XCTFail() }
    }

    func testAnAppStoreProfileCannotInstallOutsideTheStore() {
        guard case .needsAttention(let why) = IdentityStatus.evaluate(facts(kind: .appStore)) else { return XCTFail() }
        XCTAssertTrue(why.contains("App Store"), why)
    }

    func testTestResultsOverrideReadinessWhenThePairingIsFine() {
        XCTAssertEqual(IdentityStatus.evaluate(facts(test: .installed)), .verified)
        XCTAssertEqual(IdentityStatus.evaluate(facts(test: .failed)), .installFailed)
    }

    func testAPassedTestDoesNotHideAnExpiredCertificate() {
        guard case .needsAttention = IdentityStatus.evaluate(facts(valid: false, test: .installed)) else { return XCTFail() }
    }

    func testEveryStatusHasALabelAndADetail() {
        for s in [IdentityStatus.ready, .verified, .installFailed, .needsAttention("x")] {
            XCTAssertFalse(s.label.isEmpty); XCTAssertFalse(s.detail.isEmpty)
        }
    }

    func testTheTestStoreRemembersPerCertificateAndCanForget() {
        let store = InstallTestStore(defaults: UserDefaults(suiteName: "wax.test.\(UUID().uuidString)")!)
        XCTAssertNil(store.result(for: "AA"))
        store.set(.installed, for: "AA"); store.set(.failed, for: "BB")
        XCTAssertEqual(store.result(for: "AA"), .installed)
        XCTAssertEqual(store.result(for: "BB"), .failed)
        store.set(nil, for: "AA")
        XCTAssertNil(store.result(for: "AA"))
    }
}
