import XCTest
@testable import ReaderMd

/// Share is gated exactly like export, plus one guard export doesn't need:
/// a render is already in flight.
@MainActor
final class ShareGateTests: XCTestCase {

    private func loadedState() -> AppState {
        let state = AppState()
        state.selectedFile = FileNode(url: URL(fileURLWithPath: "/notes/README.md"),
                                      isDirectory: false)
        return state
    }

    func testTriggerShareBumpsTheToken() {
        let state = loadedState()
        let before = state.shareToken
        state.triggerShare()
        XCTAssertEqual(state.shareToken, before + 1)
    }

    /// The real re-entrancy guard. The toolbar greys its share row while a
    /// render is in flight, but the File menu and the command palette do not,
    /// and a second render would hand a second picker to someone who already
    /// has one open.
    func testTriggerShareIsIgnoredWhileAlreadySharing() {
        let state = loadedState()
        state.sharing = true
        let before = state.shareToken
        state.triggerShare()
        XCTAssertEqual(state.shareToken, before)
    }

    func testCanExportIsFalseWithNoDocument() {
        XCTAssertFalse(AppState().canExport)
    }

    func testCanExportIsTrueForALoadedDocument() {
        XCTAssertTrue(loadedState().canExport)
    }

    /// The diff pane renders hunks, not the document, so there is nothing to
    /// export or share from it.
    func testCanExportIsFalseWhileTheDiffPaneIsUp() {
        let state = loadedState()
        state.diffAvailable = true
        state.diffMode = true
        XCTAssertFalse(state.canExport)
    }

    /// `canShowDiff` is `diffMode && diffAvailable` — a changed file in a repo
    /// that is being *read* normally is still exportable.
    func testCanExportIsTrueForAFileInARepoWithDiffModeOff() {
        let state = loadedState()
        state.diffAvailable = true
        state.diffMode = false
        XCTAssertTrue(state.canExport)
    }

    /// A render in flight blocks a second share, but never the export beside
    /// it: concurrent exports are already supported through `activeExports`.
    func testSharingDoesNotDisableExport() {
        let state = loadedState()
        state.sharing = true
        XCTAssertTrue(state.canExport)
    }

    // MARK: Sharing the markdown itself

    func testTriggerShareSourceBumpsItsOwnToken() {
        let state = loadedState()
        let before = state.shareSourceToken
        state.triggerShareSource()
        XCTAssertEqual(state.shareSourceToken, before + 1)
        // Independent of the PDF path — one must not drive the other.
        XCTAssertEqual(state.shareToken, 0)
    }

    /// There is nothing to render, so nothing to be busy with: a PDF render in
    /// flight must not block sharing the file that is already on disk.
    func testShareSourceIsNotBlockedByAnInFlightPdfRender() {
        let state = loadedState()
        state.sharing = true
        let before = state.shareSourceToken
        state.triggerShareSource()
        XCTAssertEqual(state.shareSourceToken, before + 1)
    }

    /// Repeated presses each open a picker — no guard, unlike triggerShare().
    func testShareSourceHasNoReentrancyGuard() {
        let state = loadedState()
        state.triggerShareSource()
        state.triggerShareSource()
        XCTAssertEqual(state.shareSourceToken, 2)
    }
}
