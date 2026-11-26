import XCTest
@testable import ReaderMd

/// The update check's one decision: whether GitHub's latest release tag names a
/// later version than the running app.
final class UpdaterTests: XCTestCase {
    func testALaterTagIsNewer() {
        XCTAssertTrue(Updater.isNewer("v1.24.0", than: "1.23.0"))
        XCTAssertTrue(Updater.isNewer("v2.0.0", than: "1.99.99"))
        XCTAssertTrue(Updater.isNewer("v1.23.1", than: "1.23.0"))
    }

    func testTheSameOrAnEarlierTagIsNot() {
        XCTAssertFalse(Updater.isNewer("v1.24.0", than: "1.24.0"))
        XCTAssertFalse(Updater.isNewer("v1.23.0", than: "1.24.0"))
    }

    /// As numbers, not text: "1.10" sorts before "1.9" as a string.
    func testPartsCompareAsNumbers() {
        XCTAssertTrue(Updater.isNewer("v1.10.0", than: "1.9.0"))
        XCTAssertFalse(Updater.isNewer("v1.9.0", than: "1.10.0"))
    }

    func testAMissingPartCountsAsZero() {
        XCTAssertFalse(Updater.isNewer("v1.24", than: "1.24.0"))
        XCTAssertTrue(Updater.isNewer("v1.24.1", than: "1.24"))
    }

    func testTheVPrefixIsOptional() {
        XCTAssertTrue(Updater.isNewer("1.24.0", than: "1.23.0"))
    }

    /// A tag that isn't plain dotted numbers never prompts an update.
    func testAMalformedTagIsNeverNewer() {
        XCTAssertFalse(Updater.isNewer("v2.0.0-beta", than: "1.23.0"))
        XCTAssertFalse(Updater.isNewer("latest", than: "1.23.0"))
        XCTAssertFalse(Updater.isNewer("", than: "1.23.0"))
        XCTAssertFalse(Updater.isNewer("v1..0", than: "1.0.0"))
    }
}
