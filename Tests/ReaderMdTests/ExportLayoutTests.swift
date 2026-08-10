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
}
