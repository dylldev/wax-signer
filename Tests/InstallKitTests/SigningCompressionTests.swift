import XCTest
@testable import InstallKit

final class SigningCompressionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "SigningCompressionTests." + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testWithoutAChoiceExportsStayStandardAndPhoneInstallsKeepTheOldSwitches() {
        let d = defaults()
        let pref = SigningCompression.Preference(defaults: d)
        XCTAssertNil(pref.explicit)
        // Old default: fast compression for installs from this iPhone, standard everywhere else.
        XCTAssertEqual(pref.flags(phoneInstall: false), .init(compressChangedFiles: true, fastDeflate: false))
        XCTAssertEqual(pref.flags(phoneInstall: true), .init(compressChangedFiles: true, fastDeflate: true))
        d.set(true, forKey: SigningCompression.Preference.legacyStoreKey)
        XCTAssertEqual(pref.flags(phoneInstall: true), .init(compressChangedFiles: false, fastDeflate: true))
        XCTAssertEqual(pref.flags(phoneInstall: false), .init(compressChangedFiles: true, fastDeflate: false))
        d.set(false, forKey: SigningCompression.Preference.legacyStoreKey)
        d.set(false, forKey: SigningCompression.Preference.legacyFastKey)
        XCTAssertEqual(pref.flags(phoneInstall: true), .init(compressChangedFiles: true, fastDeflate: false))
    }

    func testPickerStartsFromTheOldSwitches() {
        let d = defaults()
        let pref = SigningCompression.Preference(defaults: d)
        XCTAssertEqual(pref.selection, .faster)   // fastDeflate defaulted to on
        d.set(false, forKey: SigningCompression.Preference.legacyFastKey)
        XCTAssertEqual(pref.selection, .standard)
        d.set(true, forKey: SigningCompression.Preference.legacyStoreKey)
        XCTAssertEqual(pref.selection, .largerFile)
        XCTAssertNil(pref.explicit, "Reading the starting selection must not count as a choice")
    }

    func testAnExplicitChoicePersistsAndAppliesToExportsAndInstallsAlike() {
        let d = defaults()
        var pref = SigningCompression.Preference(defaults: d)
        d.set(true, forKey: SigningCompression.Preference.legacyStoreKey)
        pref.choose(.standard)
        XCTAssertEqual(SigningCompression.Preference(defaults: d).explicit, .standard)
        for phone in [false, true] {
            XCTAssertEqual(pref.flags(phoneInstall: phone), .init(compressChangedFiles: true, fastDeflate: false))
        }
        pref.choose(.faster)
        for phone in [false, true] {
            XCTAssertEqual(pref.flags(phoneInstall: phone), .init(compressChangedFiles: true, fastDeflate: true))
        }
        pref.choose(.largerFile)
        for phone in [false, true] {
            XCTAssertEqual(pref.flags(phoneInstall: phone), .init(compressChangedFiles: false, fastDeflate: true))
        }
        XCTAssertEqual(SigningCompression.Preference(defaults: d).selection, .largerFile)
    }

    func testAnUnknownStoredValueFallsBackToTheOldBehavior() {
        let d = defaults()
        d.set("zstd", forKey: SigningCompression.Preference.explicitKey)
        let pref = SigningCompression.Preference(defaults: d)
        XCTAssertNil(pref.explicit)
        XCTAssertEqual(pref.flags(phoneInstall: false), .init(compressChangedFiles: true, fastDeflate: false))
    }

    func testTheNoteBeforeAChoiceDescribesTheSavedOldSwitches() {
        let d = defaults()
        let pref = SigningCompression.Preference(defaults: d)
        XCTAssertTrue(pref.note.contains("installs from this iPhone use faster compression"))
        d.set(false, forKey: SigningCompression.Preference.legacyFastKey)
        XCTAssertTrue(pref.note.contains("installs from this iPhone use standard compression"))
        d.set(true, forKey: SigningCompression.Preference.legacyStoreKey)
        XCTAssertTrue(pref.note.contains("installs from this iPhone skip compression for changed files of 2 MB or more"))
        pref.choose(.faster)
        XCTAssertFalse(pref.note.contains("Not chosen yet"))
        for n in [pref.note, SigningCompression.Preference(defaults: defaults()).note] {
            XCTAssertTrue(n.contains("Unchanged files keep their existing compression"), n)
        }
    }

    func testEveryModeSaysWhatItChangesWithoutClaimingTheWholeFile() {
        for mode in SigningCompression.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.detail.lowercased().contains("whole"))
        }
        XCTAssertTrue(SigningCompression.largerFile.detail.contains("2 MB"))
    }
}
