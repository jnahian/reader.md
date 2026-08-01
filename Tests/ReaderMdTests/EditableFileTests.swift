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
    /// once per installed copy, so the candidate list must drop both. Driven off
    /// fixture bundles rather than a real query: what `urlsForApplications`
    /// returns depends on what happens to be installed, so a test over it either
    /// asserts nothing or fails on someone else's Mac.
    func testEditorCandidatesExcludeSelfAndDuplicates() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-candidates-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let mine = "com.nahian.reader-md"
        let apps = [
            try appBundle("Reader.md.app", id: mine, in: dir),
            try appBundle("Zed.app", id: "dev.zed.Zed", in: dir),
            try appBundle("Code.app", id: "com.microsoft.VSCode", in: dir),
            // A second copy of VS Code, as LaunchServices reports one per install.
            try appBundle("Code copy.app", id: "com.microsoft.VSCode", in: dir),
        ]

        let names = AppState.editorCandidates(from: apps, excluding: mine)
            .map(\.lastPathComponent)
        XCTAssertEqual(names, ["Code.app", "Zed.app"])   // self dropped, dupe collapsed, sorted
    }

    /// Minimal on-disk app bundle — `Bundle(url:)` only needs Contents/Info.plist
    /// to report a bundle identifier.
    private func appBundle(_ name: String, id: String, in dir: URL) throws -> URL {
        let app = dir.appendingPathComponent(name)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": id], format: .xml, options: 0)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return app
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
