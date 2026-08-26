import XCTest
@testable import ReaderMd

/// Focus mode collapses the sidebar and outline and narrows the canvas — but it
/// must do so WITHOUT persisting those values, or quitting in focus mode would
/// leave the user's real layout preferences overwritten. The stash is what keeps
/// the in-memory change and the saved preference apart.
@MainActor
final class FocusModeTests: XCTestCase {
    private var savedSidebar = true
    private var savedTOC = false
    private var savedWidth = ContentWidth.wide
    private var savedFocusFullscreen = true
    private var savedFocusDimSections = true
    private var savedFocusNarrowCanvas = true
    private var savedFocusHideToolbar = true

    override func setUp() async throws {
        savedSidebar = Settings.loadShowSidebar()
        savedTOC = Settings.loadShowTOC()
        savedWidth = Settings.loadContentWidth()
        savedFocusFullscreen = Settings.loadFocusFullscreen()
        savedFocusDimSections = Settings.loadFocusDimSections()
        savedFocusNarrowCanvas = Settings.loadFocusNarrowCanvas()
        savedFocusHideToolbar = Settings.loadFocusHideToolbar()

        // Tests below flip individual focus switches, and those persist to
        // UserDefaults like any other setter. Reset to the shipped defaults
        // (all four on) so each test starts from a known baseline instead of
        // whatever an earlier test in this suite left behind.
        Settings.saveFocusFullscreen(true)
        Settings.saveFocusDimSections(true)
        Settings.saveFocusNarrowCanvas(true)
        Settings.saveFocusHideToolbar(true)
    }

    override func tearDown() async throws {
        Settings.saveShowSidebar(savedSidebar)
        Settings.saveShowTOC(savedTOC)
        Settings.saveContentWidth(savedWidth)
        Settings.saveFocusFullscreen(savedFocusFullscreen)
        Settings.saveFocusDimSections(savedFocusDimSections)
        Settings.saveFocusNarrowCanvas(savedFocusNarrowCanvas)
        Settings.saveFocusHideToolbar(savedFocusHideToolbar)
    }

    /// The in-memory layout changes; the saved preferences do not.
    func testEnteringChangesLayoutWithoutPersistingIt() {
        Settings.saveShowSidebar(true)
        Settings.saveShowTOC(true)
        Settings.saveContentWidth(.full)

        let state = AppState()
        state.showSidebar = true
        state.showTOC = true
        state.contentWidth = .full

        state.toggleFocusMode()

        XCTAssertTrue(state.focusMode)
        XCTAssertFalse(state.showSidebar)
        XCTAssertFalse(state.showTOC)
        XCTAssertEqual(state.contentWidth, .narrow)

        XCTAssertTrue(Settings.loadShowSidebar())
        XCTAssertTrue(Settings.loadShowTOC())
        XCTAssertEqual(Settings.loadContentWidth(), .full)
    }

    func testLeavingRestoresTheStashedLayout() {
        let state = AppState()
        state.showSidebar = true
        state.showTOC = false
        state.contentWidth = .full

        state.toggleFocusMode()
        state.toggleFocusMode()

        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.showSidebar)
        XCTAssertFalse(state.showTOC)
        XCTAssertEqual(state.contentWidth, .full)
    }

    /// ⌘B inside focus mode is deliberate: it persists AND updates the stash, so
    /// exiting keeps the chosen value rather than snapping back.
    func testAManualChangeInsideFocusModeWins() {
        let state = AppState()
        state.showSidebar = false
        state.contentWidth = .narrow

        state.toggleFocusMode()
        state.toggleSidebar()          // user opens the sidebar inside focus mode
        state.setContentWidth(.wide)   // and widens the canvas
        state.toggleFocusMode()

        XCTAssertTrue(state.showSidebar)
        XCTAssertEqual(state.contentWidth, .wide)
        XCTAssertTrue(Settings.loadShowSidebar())
        XCTAssertEqual(Settings.loadContentWidth(), .wide)
    }

    /// A switch that is off leaves its piece of the layout alone.
    func testDisabledSwitchesAreNoOps() {
        let state = AppState()
        state.setFocusNarrowCanvas(false)
        state.contentWidth = .full
        state.showSidebar = true

        state.toggleFocusMode()

        XCTAssertEqual(state.contentWidth, .full)
        XCTAssertFalse(state.showSidebar)   // chrome hiding is not gated on that switch
    }

    /// Dimming is only pushed to the web view when both the mode and its switch are on.
    func testFocusDimActiveNeedsBoth() {
        let state = AppState()
        XCTAssertFalse(state.focusDimActive)
        state.toggleFocusMode()
        XCTAssertTrue(state.focusDimActive)
        state.setFocusDimSections(false)
        XCTAssertFalse(state.focusDimActive)
    }
}
