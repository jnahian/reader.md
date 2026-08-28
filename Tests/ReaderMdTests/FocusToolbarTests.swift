import XCTest
@testable import ReaderMd

/// `toolbarRevealed` and `toolbarHovered` exist for two different reasons that
/// both have to un-hide the toolbar independently of one another:
///
/// - `toolbarRevealed` (⌘F): sticky until focus mode is left, so re-hiding it the
///   moment the search field clears would yank the field away from someone
///   stepping through matches with ⌘G.
/// - `toolbarHovered` (top-edge hover): transient, tracking the pointer, so the
///   toolbar comes back down the instant it moves away again.
final class FocusToolbarTests: XCTestCase {
    func testHiddenWhenModeAndSettingAreOnAndNeitherReasonToShowApplies() {
        XCTAssertTrue(focusToolbarHidden(focusMode: true, hideToolbar: true,
                                          toolbarRevealed: false, toolbarHovered: false))
    }

    func testVisibleOutsideFocusModeRegardlessOfSetting() {
        XCTAssertFalse(focusToolbarHidden(focusMode: false, hideToolbar: true,
                                           toolbarRevealed: false, toolbarHovered: false))
    }

    func testVisibleOutsideFocusModeEvenWithBothReasonsSet() {
        XCTAssertFalse(focusToolbarHidden(focusMode: false, hideToolbar: true,
                                           toolbarRevealed: true, toolbarHovered: true))
    }

    func testVisibleWhenSettingIsOff() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: false,
                                           toolbarRevealed: false, toolbarHovered: false))
    }

    func testSettingBeingOffMakesEitherReasonMoot() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: false,
                                           toolbarRevealed: true, toolbarHovered: true))
    }

    func testRevealedFlagAloneShowsToolbarDespiteSetting() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: true,
                                           toolbarRevealed: true, toolbarHovered: false))
    }

    func testHoveredFlagAloneShowsToolbarDespiteSetting() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: true,
                                           toolbarRevealed: false, toolbarHovered: true))
    }

    func testBothRevealedAndHoveredShowToolbar() {
        XCTAssertFalse(focusToolbarHidden(focusMode: true, hideToolbar: true,
                                           toolbarRevealed: true, toolbarHovered: true))
    }
}
