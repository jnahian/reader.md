import XCTest
@testable import ReaderMd

/// The reading-theme name resolver must never fail closed: an absent or
/// unrecognized persisted name (e.g. a theme removed in a future version)
/// falls back to Standard rather than crashing startup.
final class ReadingThemeTests: XCTestCase {

    func testKnownNamesResolve() {
        XCTAssertEqual(ReadingTheme.named("standard"), .standard)
        XCTAssertEqual(ReadingTheme.named("editorial"), .editorial)
        XCTAssertEqual(ReadingTheme.named("terminal"), .terminal)
    }

    func testNilFallsBackToStandard() {
        XCTAssertEqual(ReadingTheme.named(nil), .standard)
    }

    func testUnknownNameFallsBackToStandard() {
        XCTAssertEqual(ReadingTheme.named("nonexistent"), .standard)
        XCTAssertEqual(ReadingTheme.named(""), .standard)
    }

    func testCaseIterableCoversAllThree() {
        XCTAssertEqual(ReadingTheme.allCases, [.standard, .editorial, .terminal])
    }
}
