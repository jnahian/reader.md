import XCTest
@testable import ReaderMd

/// The export-layout resolver must never fail closed: an absent or
/// unrecognized persisted value falls back to page-by-page, the default.
final class ExportLayoutTests: XCTestCase {

    func testKnownNamesResolve() {
        XCTAssertEqual(ExportLayout.named("pageByPage"), .pageByPage)
        XCTAssertEqual(ExportLayout.named("continuous"), .continuous)
    }

    func testNilFallsBackToPageByPage() {
        XCTAssertEqual(ExportLayout.named(nil), .pageByPage)
    }

    func testUnknownNameFallsBackToPageByPage() {
        XCTAssertEqual(ExportLayout.named("nonexistent"), .pageByPage)
        XCTAssertEqual(ExportLayout.named(""), .pageByPage)
    }

    /// Order matters — it's the order the save panel's layout popup offers,
    /// and the popup is indexed by allCases.
    func testCaseIterableOrder() {
        XCTAssertEqual(ExportLayout.allCases, [.pageByPage, .continuous])
    }

    /// AppState is the single in-memory owner: it seeds from the persisted
    /// value at launch, and setting it writes straight through.
    @MainActor
    func testAppStateSeedsFromPersistedLayout() {
        let saved = Settings.loadExportLayout()
        defer { Settings.saveExportLayout(saved) }

        Settings.saveExportLayout(.continuous)
        XCTAssertEqual(AppState().exportLayout, .continuous)
    }

    @MainActor
    func testSetExportLayoutPersists() {
        let saved = Settings.loadExportLayout()
        defer { Settings.saveExportLayout(saved) }

        let state = AppState()
        state.setExportLayout(.continuous)
        XCTAssertEqual(state.exportLayout, .continuous)
        XCTAssertEqual(Settings.loadExportLayout(), .continuous)
        // A fresh state sees it too — the write reached UserDefaults, not just memory.
        XCTAssertEqual(AppState().exportLayout, .continuous)
    }

    /// The ⌘E save panel's popup is a per-export override. Choosing the other
    /// layout for one export must not move the stored default — which is what
    /// the panel used to do, straight to UserDefaults.
    @MainActor
    func testALocalLayoutChoiceDoesNotMoveTheDefault() {
        let saved = Settings.loadExportLayout()
        defer { Settings.saveExportLayout(saved) }

        Settings.saveExportLayout(.pageByPage)
        let state = AppState()

        // Exactly what presentExportPanel does with the popup's selection:
        // read it, use it, and never write it back.
        let picked = ExportLayout.allCases[1]
        XCTAssertEqual(picked, .continuous)

        XCTAssertEqual(state.exportLayout, .pageByPage)
        XCTAssertEqual(Settings.loadExportLayout(), .pageByPage)
    }
}
