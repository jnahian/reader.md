import XCTest
@testable import ReaderMd

/// Recents is a file list. Folder paths used to land there when a file-URL open
/// treated a directory as a document — clicking one opened a blank pane.
final class RecentPathTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentPathTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    func testMarkdownFileIsKept() throws {
        let file = tempDir.appendingPathComponent("notes.md")
        try "# hi\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(AppState.shouldKeepRecent(file.path))
    }

    func testDirectoryIsDropped() {
        XCTAssertFalse(AppState.shouldKeepRecent(tempDir.path))
    }

    /// Missing paths stay — Recents already keeps deleted files until the user
    /// clears them; this filter only rejects directories and bundled help docs.
    func testMissingPathIsKept() {
        let gone = tempDir.appendingPathComponent("gone.md")
        XCTAssertTrue(AppState.shouldKeepRecent(gone.path))
    }
}
