import XCTest
@testable import ReaderMd

/// Resume-on-reopen: the web view posts a scroll fraction on every scroll event,
/// `recordProgress` decides what's worth persisting, and `savedProgress` decides
/// what's worth restoring.
@MainActor
final class ReadingPositionTests: XCTestCase {
    private var file: FileNode!
    private var saved: [String: Double] = [:]

    override func setUp() async throws {
        // These tests share the app's real UserDefaults — put the user's own
        // reading positions back when they're done.
        saved = Settings.loadPositions()
        Settings.savePositions([:])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reading-position-\(UUID().uuidString).md")
        try "# Doc".write(to: url, atomically: true, encoding: .utf8)
        file = FileNode(url: url, isDirectory: false)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file.url)
        Settings.savePositions(saved)
    }

    func testProgressSurvivesAReopen() {
        let state = AppState()
        state.open(file)
        state.recordProgress(0.42)

        // A fresh AppState is what a relaunch actually sees.
        XCTAssertEqual(AppState().savedProgress(for: file.url.path), 0.42, accuracy: 0.0001)
    }

    func testFinishedAndBarelyStartedDocumentsOpenAtTheTop() {
        let state = AppState()
        state.open(file)

        state.recordProgress(0.99)
        XCTAssertEqual(state.savedProgress(for: file.url.path), 0, "a finished doc should not resume into its last screen")

        state.recordProgress(0.01)
        XCTAssertEqual(state.savedProgress(for: file.url.path), 0, "a doc barely scrolled has nothing to resume")
    }

    func testSubOnePercentScrollsAreNotWrittenBack() {
        let state = AppState()
        state.open(file)
        state.recordProgress(0.50)
        state.recordProgress(0.505)   // noise from a single scroll event

        XCTAssertEqual(Settings.loadPositions()[file.url.path], 0.50)
    }

    func testBundledDocsDoNotRecordAPosition() throws {
        let url = try XCTUnwrap(Bundle.resources.url(forResource: "FAQ", withExtension: "md", subdirectory: "docs"))
        let state = AppState()
        state.open(FileNode(url: url, isDirectory: false))
        state.recordProgress(0.42)

        XCTAssertTrue(Settings.loadPositions().isEmpty)
    }

    /// The diff pane posts its own scroll fraction through the same `progress`
    /// message as the document view — on render and on every scroll event. Toggling
    /// diff mode on, then scrolling around in it, must not overwrite the file's
    /// saved reading position. Needs a real git repo, the same pattern as
    /// GitDiffUntrackedFallbackTests in GitDiffTests.swift, because `canShowDiff`
    /// only goes true once AppState's async git probe confirms the file lives
    /// inside one.
    func testProgressSurvivesADiffModeToggle() async throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("diff-mode-progress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        guard case .output = GitDiff.run(["init"], in: repo) else {
            throw XCTSkip("git init failed in this environment")
        }
        defer { try? FileManager.default.removeItem(at: repo) }

        let fileURL = repo.appendingPathComponent("doc.md")
        try "# Doc".write(to: fileURL, atomically: true, encoding: .utf8)

        let state = AppState()
        state.open(FileNode(url: fileURL, isDirectory: false))
        state.recordProgress(0.60)

        // Set directly rather than via toggleDiffMode(), which persists to the
        // user's real UserDefaults — this test must not touch that preference.
        state.diffMode = true
        state.refreshDiff()

        // diffAvailable flips asynchronously once AppState's git probe (kicked off
        // in init) confirms the repo and refreshDiff's own detached task resolves.
        let deadline = Date().addingTimeInterval(5)
        while !state.canShowDiff && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard state.canShowDiff else {
            throw XCTSkip("git not available in this environment")
        }

        state.recordProgress(0.05)   // a diff-pane scroll

        XCTAssertEqual(AppState().savedProgress(for: fileURL.path), 0.60, accuracy: 0.0001,
                        "a diff-pane scroll must not overwrite the document's saved reading position")
    }
}
