import XCTest
@testable import ReaderMd
@testable import ReaderCLI

/// `isEditable` gates the Open in Editor menu item. Handing a bundled help doc,
/// a piped stdin temp, or a remote sync cache to an editor produces edits that
/// are either read-only or silently overwritten by the next pull.
@MainActor
final class EditableFileTests: XCTestCase {
    func testOrdinaryFileIsEditable() {
        XCTAssertTrue(AppState().isEditable(URL(fileURLWithPath: "/Users/someone/notes/file.md")))
    }

    func testStdinTempIsNotEditable() {
        let url = StdinDoc.directory.appendingPathComponent("1700000000-abc.md")
        XCTAssertFalse(AppState().isEditable(url))
    }

    func testBundledHelpDocIsNotEditable() throws {
        let url = try XCTUnwrap(Bundle.resources.url(forResource: "FAQ", withExtension: "md", subdirectory: "docs"))
        XCTAssertFalse(AppState().isEditable(url))
    }

    func testFileInsideARemoteRootIsNotEditable() {
        let spec = RemoteSpec(id: "test-remote", name: "Server", sshDestination: "u@h", remotePath: "/srv/docs")
        let state = AppState()
        state.roots = [RootFolder(url: spec.cacheURL, remote: spec)]
        XCTAssertFalse(state.isEditable(spec.cacheURL.appendingPathComponent("notes.md")))
    }

    /// We register as a `.md` handler ourselves and LaunchServices lists an app
    /// once per installed copy, so the candidate list must drop both.
    func testEditorCandidatesExcludeSelfAndDuplicates() {
        let candidates = AppState().editorCandidates(for: URL(fileURLWithPath: #filePath))
        let ids = candidates.compactMap { Bundle(url: $0)?.bundleIdentifier }
        XCTAssertEqual(ids.count, candidates.count)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertFalse(ids.contains("com.nahian.reader-md"))
    }

    /// An editor that's been uninstalled clears itself, so the menu stops
    /// offering a name that resolves to nothing and ⇧⌘E can ask for a new one.
    func testUninstalledEditorClearsItself() {
        let saved = Settings.loadEditorBundleID()
        defer { Settings.saveEditorBundleID(saved) }

        Settings.saveEditorBundleID("com.nonexistent.editor")
        let state = AppState()
        XCTAssertEqual(state.editorBundleID, "com.nonexistent.editor")
        XCTAssertNil(state.resolvedEditor())
        XCTAssertNil(state.editorBundleID)
        XCTAssertNil(state.editorDisplayName)
        XCTAssertNil(Settings.loadEditorBundleID())
    }

    /// A local root is not a remote — the remote check must key off `remote`,
    /// not merely off being a root.
    func testFileInsideALocalRootIsEditable() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("editable-root")
        let state = AppState()
        state.roots = [RootFolder(url: dir)]
        XCTAssertTrue(state.isEditable(dir.appendingPathComponent("notes.md")))
    }
}
