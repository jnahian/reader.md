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
}
