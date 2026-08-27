import XCTest
@testable import ReaderMd

/// The staged PDF's *name* is what AirDrop shows the receiver and what lands in
/// their Downloads, so the document's basename has to survive intact while
/// uniqueness comes from the enclosing directory.
final class ShareTempTests: XCTestCase {

    func testKeepsTheDocumentBasenameWithAPdfExtension() {
        let url = ShareTemp.url(for: "/some/deep/README.md")
        XCTAssertEqual(url.lastPathComponent, "README.pdf")
    }

    /// A path with no extension keeps its whole basename — "CHANGELOG" must not
    /// lose a component to `deletingPathExtension`.
    func testPathWithNoExtensionKeepsItsWholeName() {
        XCTAssertEqual(ShareTemp.url(for: "/notes/CHANGELOG").lastPathComponent, "CHANGELOG.pdf")
    }

    /// Only the last extension goes: "notes.v2.md" is "notes.v2", not "notes".
    func testOnlyTheFinalExtensionIsReplaced() {
        XCTAssertEqual(ShareTemp.url(for: "/notes/notes.v2.md").lastPathComponent, "notes.v2.pdf")
    }

    /// No document loaded — the same fallback the save panel already uses.
    func testNilPathFallsBackToDocument() {
        XCTAssertEqual(ShareTemp.url(for: nil).lastPathComponent, "document.pdf")
    }

    /// Two shares of the same document must not write to the same file: one
    /// render would overwrite a file the other's transfer is still reading.
    func testTwoCallsGetDifferentDirectories() {
        let a = ShareTemp.url(for: "/notes/README.md")
        let b = ShareTemp.url(for: "/notes/README.md")
        XCTAssertNotEqual(a.deletingLastPathComponent(), b.deletingLastPathComponent())
        XCTAssertEqual(a.lastPathComponent, b.lastPathComponent)
    }

    /// createPDF and the print operation both write into a path that must
    /// already exist, and neither reports a missing directory as anything
    /// louder than a file that never appears.
    func testTheEnclosingDirectoryExists() {
        let url = ShareTemp.url(for: "/notes/README.md")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path,
                                                     isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    /// Everything staged lives under one root, so launch cleanup is a single
    /// removeItem rather than a walk.
    func testStagedFilesLiveUnderTheShareRoot() {
        let url = ShareTemp.url(for: "/notes/README.md")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertTrue(url.path.hasPrefix(ShareTemp.directory.path + "/"))
    }

    /// purge() takes the whole root, including anything a previous launch left.
    func testPurgeRemovesTheShareRoot() {
        _ = ShareTemp.url(for: "/notes/README.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ShareTemp.directory.path))
        ShareTemp.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ShareTemp.directory.path))
    }
}
