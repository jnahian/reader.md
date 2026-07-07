import XCTest
@testable import ReaderMd

/// Tests for the ⌘P quick-open ranker (`fuzzyScore`). These encode the ordering
/// properties the palette relies on when it sorts matches — the actual scores
/// are implementation detail, only their relative order matters.
final class FuzzyScoreTests: XCTestCase {

    func testNonSubsequenceReturnsNil() {
        XCTAssertNil(fuzzyScore("xyz", "readme"))
        XCTAssertNil(fuzzyScore("rdx", "readme"))   // out of order
    }

    func testEmptyQueryScoresZero() {
        XCTAssertEqual(fuzzyScore("", "anything"), 0)
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(fuzzyScore("rdm", "readme"))
        XCTAssertNotNil(fuzzyScore("readme", "readme"))
    }

    func testPrefixBeatsMidStringMatch() throws {
        let prefix = try XCTUnwrap(fuzzyScore("read", "readme"))
        let mid = try XCTUnwrap(fuzzyScore("read", "unreadme"))
        XCTAssertGreaterThan(prefix, mid)
    }

    func testContiguousBeatsScattered() throws {
        let contiguous = try XCTUnwrap(fuzzyScore("abc", "abcxyz"))
        let scattered = try XCTUnwrap(fuzzyScore("abc", "axbxc"))
        XCTAssertGreaterThan(contiguous, scattered)
    }

    func testShorterTextBeatsLongerForSameMatch() throws {
        let short = try XCTUnwrap(fuzzyScore("cfg", "config.md"))
        let long = try XCTUnwrap(fuzzyScore("cfg", "config-defaults.md"))
        XCTAssertGreaterThan(short, long)
    }
}
