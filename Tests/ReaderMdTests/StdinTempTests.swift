import XCTest
@testable import ReaderMd
@testable import ReaderCLI

/// `AppState.isStdinTemp` and `StdinDoc.directory` each hardcode the same cache
/// path independently — nothing else proves they agree. A regression in either
/// one would silently re-break the recents exclusion for piped documents.
final class StdinTempTests: XCTestCase {
    func testPathInsideStdinCacheDirIsRecognized() {
        let url = StdinDoc.directory.appendingPathComponent("1700000000-abc.md")
        XCTAssertTrue(AppState.isStdinTemp(url))
    }

    func testAnOrdinaryDocumentPathIsNotAStdinTemp() {
        XCTAssertFalse(AppState.isStdinTemp(URL(fileURLWithPath: "/Users/someone/notes/file.md")))
    }

    /// A sibling directory whose name merely starts with the same prefix
    /// (e.g. "stdin-notes" next to "stdin") must not false-positive.
    func testSiblingDirectoryWithSharedPrefixIsNotAStdinTemp() {
        let sibling = StdinDoc.directory
            .deletingLastPathComponent()
            .appendingPathComponent("stdin-notes")
            .appendingPathComponent("file.md")
        XCTAssertFalse(AppState.isStdinTemp(sibling))
    }

    /// The drift check: a file actually written into `StdinDoc.directory` — the
    /// CLI's hardcoded path — must be recognized by `AppState.isStdinTemp` — the
    /// app's independently hardcoded path.
    func testStdinDocDirectoryAgreesWithIsStdinTemp() throws {
        let file = try StdinDoc.write(Data("# hi".utf8), now: Date().timeIntervalSince1970, into: StdinDoc.directory)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(AppState.isStdinTemp(file))
    }
}
