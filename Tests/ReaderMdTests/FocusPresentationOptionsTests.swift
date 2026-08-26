import XCTest
@testable import ReaderMd

/// `toolbarRevealed` exists for one race: `toggleFullScreen(nil)` is animated, and
/// `window.styleMask` can already read `.fullScreen` while it is still in flight. If
/// the user presses ⌘F in that window, `revealToolbarForFind()` sees fullscreen
/// already set and reveals the toolbar — but the `didEnterFullScreenNotification`
/// that lands moments later would otherwise re-apply `.autoHideToolbar` and silently
/// undo it. The flag makes that reapplication a no-op instead.
final class FocusPresentationOptionsTests: XCTestCase {
    func testToolbarHiddenByDefault() {
        XCTAssertEqual(focusPresentationOptions(hideToolbar: true, toolbarRevealed: false),
                       [.autoHideMenuBar, .autoHideToolbar])
    }

    func testToolbarStaysHiddenWhenSettingIsOff() {
        XCTAssertEqual(focusPresentationOptions(hideToolbar: false, toolbarRevealed: false),
                       [.autoHideMenuBar])
    }

    func testRevealedFlagSuppressesAutoHideToolbar() {
        XCTAssertEqual(focusPresentationOptions(hideToolbar: true, toolbarRevealed: true),
                       [.autoHideMenuBar])
    }

    func testRevealedFlagIsMootWhenToolbarWasNeverHidden() {
        XCTAssertEqual(focusPresentationOptions(hideToolbar: false, toolbarRevealed: true),
                       [.autoHideMenuBar])
    }
}
