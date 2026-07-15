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

    /// "github" was a real theme in 1.10.0, removed in 1.11.0. Anyone who had it
    /// selected must land on Standard, not crash — the migration path for the removal.
    func testRemovedGithubNameFallsBackToStandard() {
        XCTAssertEqual(ReadingTheme.named("github"), .standard)
    }

    func testNilFallsBackToStandard() {
        XCTAssertEqual(ReadingTheme.named(nil), .standard)
    }

    func testUnknownNameFallsBackToStandard() {
        XCTAssertEqual(ReadingTheme.named("nonexistent"), .standard)
        XCTAssertEqual(ReadingTheme.named(""), .standard)
    }

    /// Order matters — it's the order the theme picker offers them in.
    func testCaseIterableCoversEveryTheme() {
        XCTAssertEqual(ReadingTheme.allCases, [.standard, .editorial, .terminal])
    }
}
