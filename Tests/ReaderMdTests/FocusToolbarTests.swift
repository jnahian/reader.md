import XCTest
@testable import ReaderMd

/// `toolbarRevealed` exists for one reason: ⌘F must bring the toolbar back without
/// costing the mode, and the reveal has to be sticky until focus mode is left —
/// re-hiding it the moment the search field clears would yank the field away from
/// someone stepping through matches with ⌘G.
final class FocusToolbarTests: XCTestCase {
    func testHiddenWhenModeAndSettingAreOnAndNotRevealed() {
        XCTAssertTrue(focusToolbarHidden(focusMode: true, hideToolbar: true, toolbarRevealed: false))
    }

    func testVisibleOutsideFocusModeRegardlessOfSetting() {
        XCTAssertFalse(focusToolbarHidden(focusMode: false, hideToolbar: true, toolbarRevealed: false))
    }

    func testVisibleWhenSettingIsOff() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: false, toolbarRevealed: false))
    }

    func testRevealedFlagShowsToolbarDespiteSetting() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: true, toolbarRevealed: true))
    }

    func testRevealedFlagIsMootWhenToolbarWasNeverHidden() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: false, toolbarRevealed: true))
    }
}
