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
        XCTAssertTrue(AppState.shouldKeepListed(file.path))
    }

    func testDirectoryIsDropped() {
        XCTAssertFalse(AppState.shouldKeepListed(tempDir.path))
    }

    /// A folder that reached Recents could have been pinned from its context menu,
    /// and a pinned folder row would open as a root rather than a document.
    func testDirectoryCannotBeFavorited() {
        XCTAssertFalse(AppState.canFavorite(tempDir))
    }

    /// Missing paths stay — Recents already keeps deleted files until the user
    /// clears them; this filter only rejects directories and bundled help docs.
    func testMissingPathIsKept() {
        let gone = tempDir.appendingPathComponent("gone.md")
        XCTAssertTrue(AppState.shouldKeepListed(gone.path))
    }

    /// marked percent-encodes hrefs, so a link to a file with a space in its name
    /// arrives as `%20` and has to be decoded before it resolves.
    func testEncodedLinkResolvesToRealFile() throws {
        let file = tempDir.appendingPathComponent("My Note.md")
        try "# hi\n".write(to: file, atomically: true, encoding: .utf8)
        let encoded = tempDir.path + "/My%20Note.md"
        XCTAssertEqual(AppState.resolvedPath(encoded), file.path)
    }

    /// That encoding isn't reversible — marked leaves a real `%` alone — so a file
    /// literally named `a%20b.md` must win over the decoded spelling.
    func testLiteralPercentFilenameWinsOverDecoding() throws {
        let file = tempDir.appendingPathComponent("a%20b.md")
        try "# hi\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(AppState.resolvedPath(file.path), file.path)
    }

    /// Nothing to resolve against: hand the path back untouched so the caller still
    /// selects it and the user can remove the stale entry.
    func testMissingPathIsReturnedUnchanged() {
        let gone = tempDir.path + "/gone%20file.md"
        XCTAssertEqual(AppState.resolvedPath(gone), gone)
    }
}
