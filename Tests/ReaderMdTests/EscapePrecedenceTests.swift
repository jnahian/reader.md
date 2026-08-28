import XCTest
@testable import ReaderMd

/// Esc is consumed inside the web view while reading, so focus mode's exit arrives
/// as a message rather than a key equivalent. Everything Esc already did has to keep
/// working, which makes the order the whole feature: a search clears first, ⌘P
/// dismisses first, and focus mode exits only when there is nothing else to dismiss.
final class EscapePrecedenceTests: XCTestCase {
    func testFindWinsOverEverything() {
        XCTAssertEqual(escapeAction(findQuery: "abc", showQuickOpen: true, focusMode: true), .clearFind)
        XCTAssertEqual(escapeAction(findQuery: "abc", showQuickOpen: false, focusMode: true), .clearFind)
        XCTAssertEqual(escapeAction(findQuery: "abc", showQuickOpen: false, focusMode: false), .clearFind)
    }

    func testQuickOpenWinsOverFocusMode() {
        XCTAssertEqual(escapeAction(findQuery: "", showQuickOpen: true, focusMode: true), .dismissQuickOpen)
        XCTAssertEqual(escapeAction(findQuery: "", showQuickOpen: true, focusMode: false), .dismissQuickOpen)
    }

    func testFocusModeExitsWhenNothingElseIsUp() {
        XCTAssertEqual(escapeAction(findQuery: "", showQuickOpen: false, focusMode: true), .exitFocusMode)
    }

    func testEscDoesNothingWhenIdle() {
        XCTAssertEqual(escapeAction(findQuery: "", showQuickOpen: false, focusMode: false), .ignore)
    }

    /// A whitespace-only query is still a query — the field has text in it to clear.
    func testWhitespaceQueryStillClears() {
        XCTAssertEqual(escapeAction(findQuery: " ", showQuickOpen: false, focusMode: true), .clearFind)
    }

    @MainActor
    func testHandleEscapeExitsFocusMode() {
        let state = AppState()
        state.toggleFocusMode()
        state.handleEscapeFromPage()
        XCTAssertFalse(state.focusMode)
    }
}
