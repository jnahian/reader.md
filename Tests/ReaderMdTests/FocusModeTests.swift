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
    private var savedFocusDimSections = false
    private var savedFocusNarrowCanvas = true
    private var savedFocusHideToolbar = true
    private var savedFocusRegionDepth = FocusRegionDepth.h3
    private var savedFocusDimOpacity = 0.38

    override func setUp() async throws {
        savedSidebar = Settings.loadShowSidebar()
        savedTOC = Settings.loadShowTOC()
        savedWidth = Settings.loadContentWidth()
        savedFocusFullscreen = Settings.loadFocusFullscreen()
        savedFocusDimSections = Settings.loadFocusDimSections()
        savedFocusNarrowCanvas = Settings.loadFocusNarrowCanvas()
        savedFocusHideToolbar = Settings.loadFocusHideToolbar()
        savedFocusRegionDepth = Settings.loadFocusRegionDepth()
        savedFocusDimOpacity = Settings.loadFocusDimOpacity()

        // Tests below flip individual focus switches, and those persist to
        // UserDefaults like any other setter. Pin the shipped defaults so each
        // test starts from a known baseline instead of whatever an earlier test
        // left behind — except dimming, which ships off and is pinned on here so
        // the dimming tests have something to assert.
        Settings.saveFocusFullscreen(true)
        Settings.saveFocusDimSections(true)
        Settings.saveFocusNarrowCanvas(true)
        Settings.saveFocusHideToolbar(true)
        Settings.saveFocusRegionDepth(.h3)
        Settings.saveFocusDimOpacity(0.38)
    }

    override func tearDown() async throws {
        Settings.saveShowSidebar(savedSidebar)
        Settings.saveShowTOC(savedTOC)
        Settings.saveContentWidth(savedWidth)
        Settings.saveFocusFullscreen(savedFocusFullscreen)
        Settings.saveFocusDimSections(savedFocusDimSections)
        Settings.saveFocusNarrowCanvas(savedFocusNarrowCanvas)
        Settings.saveFocusHideToolbar(savedFocusHideToolbar)
        Settings.saveFocusRegionDepth(savedFocusRegionDepth)
        Settings.saveFocusDimOpacity(savedFocusDimOpacity)
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

    // MARK: - Configurable dimming

    /// Dimming is opt-in, and when it is switched on the region is a section
    /// down to `h3` rather than every heading.
    func testDimmingDefaultsToOffAtH3() {
        Settings.defaults.removeObject(forKey: "reader.md.focus.dimSections")
        Settings.defaults.removeObject(forKey: "reader.md.focus.regionDepth")
        Settings.defaults.removeObject(forKey: "reader.md.focus.dimOpacity")

        XCTAssertFalse(Settings.loadFocusDimSections())
        XCTAssertEqual(Settings.loadFocusRegionDepth(), .h3)
        XCTAssertEqual(Settings.loadFocusDimOpacity(), 0.38, accuracy: 0.0001)
    }

    /// The other three switches are the mode's advertised takeover, so they stay
    /// on out of the box.
    func testTheOtherThreeSwitchesDefaultOn() {
        Settings.defaults.removeObject(forKey: "reader.md.focus.fullscreen")
        Settings.defaults.removeObject(forKey: "reader.md.focus.narrowCanvas")
        Settings.defaults.removeObject(forKey: "reader.md.focus.hideToolbar")

        XCTAssertTrue(Settings.loadFocusFullscreen())
        XCTAssertTrue(Settings.loadFocusNarrowCanvas())
        XCTAssertTrue(Settings.loadFocusHideToolbar())
    }

    /// An absent key must not read as 0: `defaults.integer` would make depth 0
    /// (no valid heading level) and `defaults.double` would make the document
    /// invisible.
    func testAbsentKeysDoNotReadAsZero() {
        Settings.defaults.removeObject(forKey: "reader.md.focus.regionDepth")
        Settings.defaults.removeObject(forKey: "reader.md.focus.dimOpacity")

        XCTAssertNotEqual(Settings.loadFocusRegionDepth().rawValue, 0)
        XCTAssertGreaterThan(Settings.loadFocusDimOpacity(), 0)
    }

    func testDimmingPreferencesRoundTrip() {
        let state = AppState()

        state.setFocusRegionDepth(.h2)
        state.setFocusDimOpacity(0.5)

        XCTAssertEqual(state.focusRegionDepth, .h2)
        XCTAssertEqual(state.focusDimOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(Settings.loadFocusRegionDepth(), .h2)
        XCTAssertEqual(Settings.loadFocusDimOpacity(), 0.5, accuracy: 0.0001)
    }

    /// The value is interpolated into a CSS custom property, so the clamp is the
    /// only thing between a bad write and unreadable or invisible content.
    func testOpacityClampsAtBothEnds() {
        let state = AppState()

        state.setFocusDimOpacity(0.9)
        XCTAssertEqual(state.focusDimOpacity, 0.60, accuracy: 0.0001)

        state.setFocusDimOpacity(0)
        XCTAssertEqual(state.focusDimOpacity, 0.12, accuracy: 0.0001)
    }

    /// A depth stored by a future build (or corrupted) must not become a depth of
    /// 0, which would produce an empty boundary list and silently kill dimming.
    func testUnknownStoredDepthFallsBackToTheDefault() {
        Settings.defaults.set(99, forKey: "reader.md.focus.regionDepth")

        XCTAssertEqual(Settings.loadFocusRegionDepth(), .h3)
    }

    /// The preview widens what counts as "dimming is showing" — never what counts
    /// as "focus mode is on".
    func testPreviewDimsWithoutEnteringFocusMode() {
        let state = AppState()
        XCTAssertFalse(state.focusDimActive)

        state.focusDimPreview = true

        XCTAssertTrue(state.focusDimActive)
        XCTAssertFalse(state.focusMode)
    }

    /// With the dimming switch off there is nothing to preview.
    func testPreviewRespectsTheDimmingSwitch() {
        let state = AppState()
        state.setFocusDimSections(false)

        state.focusDimPreview = true

        XCTAssertFalse(state.focusDimActive)
    }
}
