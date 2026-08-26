# Focus Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One toggle (⌥⌘F) that strips Reader.md down to the page — chrome hidden, window fullscreen, every section but the one being read dimmed — with each of its four pieces switchable in Settings.

**Architecture:** A `focusMode` flag on `AppState` plus a non-`@Published` `FocusStash` that captures the pre-focus layout so focus mode never writes the user's real preferences to `UserDefaults`. Dimming lives entirely in `bridge.js`: `reportActiveHeading()` already computes the active heading locally, so it also classes the sibling blocks outside that heading's region — Swift's only involvement is one `setFocusDim(bool)` per toggle, and nothing new is published at scroll rate. Fullscreen and toolbar hiding go through the `NSWindow` that `WindowAccessor` already hands to `AppState`.

**Tech Stack:** Swift 6.2 / SwiftUI / AppKit, WKWebView + vanilla JS (`bridge.js`), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-27-focus-mode-design.md`

## Global Constraints

- Deployment target is **macOS 13**. Any macOS 26-only API needs an availability guard with a pre-26 fallback. Nothing in this plan should need one.
- Build toolchain is **Xcode 26 / Swift 6.2+ with the macOS 26 SDK**.
- `AppState` is `@MainActor ObservableObject`. Tests that touch it must be `@MainActor`.
- **Nothing new may be published at scroll or keystroke rate on `AppState`.** That rule is why `ReadingState` exists. This feature adds nothing to either — the active heading is already known locally in JS at the moment it is needed.
- Tests share the app's **real `UserDefaults`**. Every test that writes a preference must save the user's value in `setUp` and restore it in `tearDown`, following `Tests/ReaderMdTests/FavoritesTests.swift`.
- The `.keyboardShortcut` bindings in `ReaderMdApp.swift` are the authority for what a key does. The new binding is **⌥⌘F** — `.keyboardShortcut("f", modifiers: [.command, .option])`. It is free today.
- `ShortcutDocTests` fails the build if a shortcut appears in the bundled `SHORTCUTS.md` without a matching row in `docs/features.md`. Task 7 moves both together.
- UI convention: chrome buttons carry a `.dockTooltip("Label (⇧⌘X)")` with the shortcut in parentheses.
- Build with `swift build`; run the suite with `swift test`; run the app with `swift run ReaderMd`.

---

### Task 1: Focus state, the stash, and the Settings keys

The stash is the whole reason this task exists. `showSidebar`, `showTOC`, and `contentWidth` persist to `UserDefaults` on write, so if focus mode used `toggleSidebar()` / `setShowTOC()` / `setContentWidth()`, quitting while in focus mode would leave the user's real preferences overwritten — they would return to a collapsed sidebar and narrow text with no focus mode on.

**Files:**
- Modify: `Sources/ReaderMd/Models/Settings.swift`
- Modify: `Sources/ReaderMd/Models/AppState.swift`
- Test: `Tests/ReaderMdTests/FocusModeTests.swift` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `AppState.focusMode: Bool` (`@Published`, private setter not required — read by views)
  - `AppState.toggleFocusMode()`
  - `AppState.focusFullscreen / focusDimSections / focusNarrowCanvas / focusHideToolbar: Bool` (`@Published`) and their setters `setFocusFullscreen(_:)`, `setFocusDimSections(_:)`, `setFocusNarrowCanvas(_:)`, `setFocusHideToolbar(_:)`
  - `AppState.focusDimActive: Bool` — computed: `focusMode && focusDimSections`. Task 3 pushes this to JS.
  - `Settings.loadFocusFullscreen() / saveFocusFullscreen(_:)` and the same three pairs for the other switches.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReaderMdTests/FocusModeTests.swift`:

```swift
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

    override func setUp() async throws {
        savedSidebar = Settings.loadShowSidebar()
        savedTOC = Settings.loadShowTOC()
        savedWidth = Settings.loadContentWidth()
    }

    override func tearDown() async throws {
        Settings.saveShowSidebar(savedSidebar)
        Settings.saveShowTOC(savedTOC)
        Settings.saveContentWidth(savedWidth)
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter FocusModeTests`
Expected: FAIL to compile — `value of type 'AppState' has no member 'toggleFocusMode'`.

- [ ] **Step 3: Add the four Settings keys**

In `Sources/ReaderMd/Models/Settings.swift`, add to the key block near `showSidebarKey`:

```swift
    private static let focusFullscreenKey = "reader.md.focus.fullscreen"
    private static let focusDimSectionsKey = "reader.md.focus.dimSections"
    private static let focusNarrowCanvasKey = "reader.md.focus.narrowCanvas"
    private static let focusHideToolbarKey = "reader.md.focus.hideToolbar"
```

And after the Sidebar block, add:

```swift
    // Focus mode. All four default on: the mode's advertised behaviour is the
    // full takeover, and each switch only subtracts from it.
    static func loadFocusFullscreen() -> Bool {
        defaults.object(forKey: focusFullscreenKey) as? Bool ?? true
    }
    static func saveFocusFullscreen(_ value: Bool) {
        defaults.set(value, forKey: focusFullscreenKey)
    }

    static func loadFocusDimSections() -> Bool {
        defaults.object(forKey: focusDimSectionsKey) as? Bool ?? true
    }
    static func saveFocusDimSections(_ value: Bool) {
        defaults.set(value, forKey: focusDimSectionsKey)
    }

    static func loadFocusNarrowCanvas() -> Bool {
        defaults.object(forKey: focusNarrowCanvasKey) as? Bool ?? true
    }
    static func saveFocusNarrowCanvas(_ value: Bool) {
        defaults.set(value, forKey: focusNarrowCanvasKey)
    }

    static func loadFocusHideToolbar() -> Bool {
        defaults.object(forKey: focusHideToolbarKey) as? Bool ?? true
    }
    static func saveFocusHideToolbar(_ value: Bool) {
        defaults.set(value, forKey: focusHideToolbarKey)
    }
```

- [ ] **Step 4: Add the state and the stash to `AppState`**

In `Sources/ReaderMd/Models/AppState.swift`, alongside the other layout properties (near `@Published var showSidebar`):

```swift
    // MARK: - Focus mode

    @Published var focusMode: Bool = false

    @Published var focusFullscreen: Bool = Settings.loadFocusFullscreen()
    @Published var focusDimSections: Bool = Settings.loadFocusDimSections()
    @Published var focusNarrowCanvas: Bool = Settings.loadFocusNarrowCanvas()
    @Published var focusHideToolbar: Bool = Settings.loadFocusHideToolbar()

    /// What the web view is told. Dimming needs both the mode and its switch.
    var focusDimActive: Bool { focusMode && focusDimSections }

    /// Every switch off makes ⌥⌘F a no-op. Settings shows a note when this is true.
    var focusModeDoesNothing: Bool {
        !focusFullscreen && !focusDimSections && !focusNarrowCanvas && !focusHideToolbar
    }

    /// The layout as it was before focus mode took it over.
    ///
    /// Deliberately not `@Published` — nothing renders from it. Deliberately not
    /// written through `toggleSidebar()` / `setShowTOC()` / `setContentWidth()`
    /// either: those persist to UserDefaults, and focus mode's values must never
    /// become the user's saved preferences.
    struct FocusStash {
        var showSidebar: Bool
        var showTOC: Bool
        var contentWidth: ContentWidth
        var wasAlreadyFullscreen: Bool
    }
    private(set) var focusStash: FocusStash?
```

- [ ] **Step 5: Add the toggle and the switch setters**

In the `// MARK: - Layout` section of `AppState.swift`, after `toggleSidebar()`:

```swift
    func toggleFocusMode() {
        focusMode ? exitFocusMode() : enterFocusMode()
    }

    private func enterFocusMode() {
        let alreadyFullscreen = documentWindow?.styleMask.contains(.fullScreen) ?? false
        focusStash = FocusStash(showSidebar: showSidebar,
                                showTOC: showTOC,
                                contentWidth: contentWidth,
                                wasAlreadyFullscreen: alreadyFullscreen)
        focusMode = true

        // Direct writes, not the setters — see FocusStash.
        showSidebar = false
        showTOC = false
        if focusNarrowCanvas { contentWidth = .narrow }
    }

    private func exitFocusMode() {
        focusMode = false
        guard let stash = focusStash else { return }
        focusStash = nil
        showSidebar = stash.showSidebar
        showTOC = stash.showTOC
        contentWidth = stash.contentWidth
    }

    func setFocusFullscreen(_ value: Bool) {
        focusFullscreen = value
        Settings.saveFocusFullscreen(value)
    }

    func setFocusDimSections(_ value: Bool) {
        focusDimSections = value
        Settings.saveFocusDimSections(value)
    }

    func setFocusNarrowCanvas(_ value: Bool) {
        focusNarrowCanvas = value
        Settings.saveFocusNarrowCanvas(value)
    }

    func setFocusHideToolbar(_ value: Bool) {
        focusHideToolbar = value
        Settings.saveFocusHideToolbar(value)
    }
```

- [ ] **Step 6: Make manual changes inside focus mode update the stash**

Still in `AppState.swift`, amend the three existing setters so a deliberate change
inside focus mode survives the exit. Replace `toggleSidebar()`:

```swift
    func toggleSidebar() {
        showSidebar.toggle()
        Settings.saveShowSidebar(showSidebar)
        focusStash?.showSidebar = showSidebar
    }
```

Replace `setShowTOC(_:)`:

```swift
    func setShowTOC(_ value: Bool) {
        showTOC = value
        Settings.saveShowTOC(value)
        focusStash?.showTOC = value
    }
```

Replace `setContentWidth(_:)`:

```swift
    func setContentWidth(_ value: ContentWidth) {
        contentWidth = value
        Settings.saveContentWidth(value)
        focusStash?.contentWidth = value
    }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter FocusModeTests`
Expected: PASS, 5 tests.

- [ ] **Step 8: Run the whole suite**

Run: `swift test`
Expected: PASS. `toggleSidebar` / `setShowTOC` / `setContentWidth` gained a line each; nothing else changed behaviour.

- [ ] **Step 9: Commit**

```bash
git add Sources/ReaderMd/Models/Settings.swift Sources/ReaderMd/Models/AppState.swift Tests/ReaderMdTests/FocusModeTests.swift
git commit -m "feat(focus): focus mode state, layout stash, and Settings keys"
```

---

### Task 2: The Esc precedence chain

Esc never reaches AppKit while reading — `bridge.js` consumes it in two `keydown` listeners (the Mermaid overlay at `bridge.js:525`, the image lightbox at `bridge.js:661`). Task 3 posts an `exitFocus` message from JS; this task builds the decision it feeds, as a pure function so it can be table-tested.

The in-page overlay cases never reach Swift — `bridge.js` resolves them before posting — so the function takes three booleans, not four.

**Files:**
- Modify: `Sources/ReaderMd/Models/AppState.swift`
- Test: `Tests/ReaderMdTests/EscapePrecedenceTests.swift` (create)

**Interfaces:**
- Consumes: `AppState.focusMode` from Task 1.
- Produces:
  - `enum EscapeAction { case clearFind, dismissQuickOpen, exitFocusMode, none }` — module scope, in `AppState.swift`
  - `func escapeAction(findQuery: String, showQuickOpen: Bool, focusMode: Bool) -> EscapeAction` — a free function, module scope
  - `AppState.handleEscapeFromPage()` — applies it. Task 3 calls this.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ReaderMdTests/EscapePrecedenceTests.swift`:

```swift
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
        XCTAssertEqual(escapeAction(findQuery: "", showQuickOpen: false, focusMode: false), .none)
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter EscapePrecedenceTests`
Expected: FAIL to compile — `cannot find 'escapeAction' in scope`.

- [ ] **Step 3: Write the function and the handler**

At module scope in `Sources/ReaderMd/Models/AppState.swift`, below the `AppState` class:

```swift
/// What Escape should do when it arrives from the page.
///
/// A free function over three booleans rather than a method, so the ordering — the
/// only part of this that can silently regress — is testable without a window.
/// The in-page overlays (Mermaid fullscreen, the image lightbox) never reach here:
/// `bridge.js` resolves them before posting.
enum EscapeAction: Equatable {
    case clearFind
    case dismissQuickOpen
    case exitFocusMode
    case none
}

func escapeAction(findQuery: String, showQuickOpen: Bool, focusMode: Bool) -> EscapeAction {
    if !findQuery.isEmpty { return .clearFind }
    if showQuickOpen { return .dismissQuickOpen }
    if focusMode { return .exitFocusMode }
    return .none
}
```

And as a method on `AppState`, in the focus mode section:

```swift
    /// Escape, arriving from the web view. See `escapeAction` for the ordering.
    func handleEscapeFromPage() {
        switch escapeAction(findQuery: findQuery,
                            showQuickOpen: showQuickOpen,
                            focusMode: focusMode) {
        case .clearFind: findQuery = ""
        case .dismissQuickOpen: showQuickOpen = false
        case .exitFocusMode: toggleFocusMode()
        case .none: break
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter EscapePrecedenceTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ReaderMd/Models/AppState.swift Tests/ReaderMdTests/EscapePrecedenceTests.swift
git commit -m "feat(focus): Escape precedence — find, then quick open, then focus mode"
```

---

### Task 3: Section dimming and the Escape message in the web view

`reportActiveHeading()` already walks `h1,h2,h3,h4` and picks the topmost heading above 100px, then posts the id to Swift. It gains a second job: classing the sibling blocks outside that heading's region.

**No `<section>` wrappers.** marked emits a flat `h2, p, p, h2, …` sibling list, and mark anchoring (`TextAnchor`), find, footnotes, and diff hunks all read that flat structure — wrapping would break anchor resolution silently.

The region runs from the active heading to the **next heading at any level**. Same-or-higher-level was rejected in the spec: with `h2 A / p / h3 A.1 / p / h2 B`, scrolling `A.1` from `top: 90px` to `top: 110px` flips the active heading from `A.1` to `A`, and a same-or-higher rule would swing the lit region from one paragraph to the whole of A — a large block fading in and out over a 20px scroll, which is the exact artifact section dimming was chosen to avoid.

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/template.html` (the `<style>` block, lines 8–272)
- Modify: `Sources/ReaderMd/Resources/web/bridge.js`
- Modify: `Sources/ReaderMd/Views/MarkdownWebView.swift`

**Interfaces:**
- Consumes: `AppState.focusDimActive` and `AppState.handleEscapeFromPage()` from Tasks 1–2.
- Produces:
  - JS: `window.ReaderMd.setFocusDim(on)`
  - JS → Swift message name `"exitFocus"`
  - Swift: `MarkdownWebView.Coordinator.applyFocusDim(_ on: Bool)`

- [ ] **Step 1: Add the CSS rule**

In `Sources/ReaderMd/Resources/web/template.html`, inside the `<style>` block (before the closing `</style>` at line 272):

```css
      /* Focus mode: everything outside the current heading's region. Dimmed, not
         hidden — 0.38 stays legible, so glancing back at the previous section
         does not require leaving the mode. */
      .focus-dim { opacity: .38; transition: opacity .2s ease; }
```

- [ ] **Step 2: Add the dimming pass to `bridge.js`**

In `Sources/ReaderMd/Resources/web/bridge.js`, immediately above `function reportActiveHeading()`:

```js
let focusDim = false;

// Classes the top-level blocks OUTSIDE the active heading's region. Deliberately
// no <section> wrappers: marked emits a flat h2/p/p/h2 sibling list, and mark
// anchoring, find, footnotes and diff hunks all read that flat structure.
//
// The region ends at the next heading of ANY level. Ending it at the next
// same-or-higher heading would make a 20px scroll across a nested heading swing
// the lit region between a paragraph and its whole parent section.
function applyFocusDim() {
  const blocks = [...contentEl.children];
  for (const b of blocks) b.classList.remove('focus-dim');

  // Suspended while a search is active (a match inside a dimmed section is hard
  // to spot) and in diff mode (the spy tracks hunks, and the layout is
  // side-by-side).
  if (!focusDim || diffMode || findQuery) return;

  const headings = [];
  blocks.forEach((b, i) => { if (/^H[1-4]$/.test(b.tagName)) headings.push(i); });
  // One region means dimming has nothing to say.
  if (headings.length < 2) return;

  let active = headings[0];
  for (const i of headings) {
    if (blocks[i].getBoundingClientRect().top <= 100) active = i;
    else break;
  }
  const next = headings.find((i) => i > active) ?? blocks.length;
  blocks.forEach((b, i) => { if (i < active || i >= next) b.classList.add('focus-dim'); });
}
```

- [ ] **Step 3: Call it from the three places it has to run**

The scroll spy is wired only to `scroll`, so toggling while stationary and a
freshly rendered document both need an explicit pass.

**3a.** At the end of `reportActiveHeading()` in `bridge.js`, after `post('activeHeading', activeId);`:

```js
  applyFocusDim();
```

**3b.** At the end of `applyFindQuery()` (it is the single place `findQuery` changes), after `setCurrentFind(focus, scroll);`:

```js
  applyFocusDim();
```

Also add the same line to the two early-return branches in `applyFindQuery` that
post `{ count: 0, index: 0 }` — clearing a search must un-suspend dimming. Each
becomes, for example:

```js
  if (!q) { findFocus = 0; post('findResult', { count: 0, index: 0 }); applyFocusDim(); return; }
```

**3c.** In the `window.ReaderMd` object, beside `setContentWidth`:

```js
  setFocusDim(on) {
    focusDim = on;
    applyFocusDim();
  },
```

**3d.** A rebuilt DOM has lost the classes. At the end of `render()` — the function `loadMarkdown` and `reloadMarkdown` both call — add:

```js
  applyFocusDim();
```

- [ ] **Step 4: Post `exitFocus` from the Escape listener**

Replace the listener at `bridge.js:524-529` (`// One listener for the whole document…`) with:

```js
// One listener for the whole document rather than one per diagram; inert unless
// something is actually open. Anything Escape does NOT consume in the page is
// handed to Swift, which owns the precedence (find, quick open, focus mode).
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const open = document.querySelector('.mm-view.fs');
  if (open) { exitFullscreen(open); return; }
  // The lightbox has its own listener further down; it fires after this one, so
  // check the state directly rather than relying on ordering.
  const lightbox = document.getElementById('lightbox');
  if (lightbox && lightbox.classList.contains('open')) return;
  post('exitFocus', true);
});
```

The message is posted unconditionally rather than only when focus mode is on — JS does not know the mode, and `escapeAction` already has a `.none` branch for "nothing to dismiss."

- [ ] **Step 5: Register the message name — this fails silently if skipped**

In `Sources/ReaderMd/Views/MarkdownWebView.swift:91-93`, add `"exitFocus"` to the array. A `post()` whose name is absent does nothing and raises no error:

```swift
        let messageNames = ["ready", "toc", "activeHeading", "openExternal", "openFile", "wordCount", "progress",
                             "rendered", "textSelected", "markClicked", "marksApplied", "findResult",
                             "diagramFullscreen", "exitFocus"]
```

- [ ] **Step 6: Handle the message**

In the `userContentController(_:didReceive:)` switch in `MarkdownWebView.swift`, beside `case "diagramFullscreen":`:

```swift
            case "exitFocus":
                // Escape reached the page without being consumed there. Swift owns
                // the precedence — see `escapeAction`.
                Task { @MainActor in self.state.handleEscapeFromPage() }
```

- [ ] **Step 7: Push the flag from Swift**

In the `Coordinator`, beside `applyTypography(scale:width:)`:

```swift
        private var lastFocusDim: Bool?

        func applyFocusDim(_ on: Bool) {
            guard isReady else { lastFocusDim = on; return }
            guard lastFocusDim != on else { return }
            lastFocusDim = on
            webView?.evaluateJavaScript("window.ReaderMd.setFocusDim(\(on));")
        }
```

In `updateNSView`, after the `coord.applyTypography(...)` line:

```swift
        coord.applyFocusDim(state.focusDimActive)
```

And in the `case "ready":` replay block, after the `lastWidth` line:

```swift
                if let dim = lastFocusDim { webView?.evaluateJavaScript("window.ReaderMd.setFocusDim(\(dim));") }
```

- [ ] **Step 8: Build and run the app**

Run: `swift build`
Expected: builds clean.

Run: `swift run ReaderMd`, open a document with at least two headings, and check by hand — this is web-view behaviour and `swift test` cannot reach it:
- Nothing is dimmed before focus mode is on.
- Toggling focus mode from the View menu dims immediately, **without scrolling first** (this is what Step 3c's `applyFocusDim()` call buys).
- Scrolling within one section changes nothing; crossing a heading fades two adjacent regions.
- Typing in the find field un-dims the whole document; clearing it re-dims.
- ⇧⌘D into diff mode un-dims.
- ⌘R re-renders and the dimming survives.
- Escape with a search active clears the search rather than exiting focus mode.

- [ ] **Step 9: Commit**

```bash
git add Sources/ReaderMd/Resources/web/template.html Sources/ReaderMd/Resources/web/bridge.js Sources/ReaderMd/Views/MarkdownWebView.swift
git commit -m "feat(focus): dim sections outside the active heading, and route Escape out of the page"
```

---

### Task 4: The native controls — shortcut, menu, toolbar button, palette command

**Files:**
- Modify: `Sources/ReaderMd/ReaderMdApp.swift:120-147` (the `CommandGroup(after: .toolbar)` block)
- Modify: `Sources/ReaderMd/Views/Toolbar.swift` (the View `ToolbarItemGroup(placement: .primaryAction)`)
- Modify: `Sources/ReaderMd/Views/QuickOpenView.swift:217-232` (`paletteCommands`)
- Modify: `Sources/ReaderMd/ContentView.swift:83`

**Interfaces:**
- Consumes: `AppState.focusMode` and `AppState.toggleFocusMode()` from Task 1.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Verify the toolbar icon exists on the deployment target**

`rectangle.center.inset.filled` is believed to be SF Symbols 3 and therefore present on macOS 13, but a symbol missing from the target's catalogue renders **blank** rather than falling back — so confirm rather than assume.

Run: `open -a "SF Symbols"` and search `rectangle.center.inset.filled`; its availability line must read macOS 12.0 or earlier.

If it is **not** available on macOS 13, use `rectangle.inset.filled` for both states throughout this task and carry the on-state with `.symbolVariant(.fill)` omitted — i.e. drop the ternary and let the toolbar item's own selected styling show the state. Note the substitution in the commit message.

- [ ] **Step 2: Add the menu item and the ⌥⌘F binding**

In `Sources/ReaderMd/ReaderMdApp.swift`, in `CommandGroup(after: .toolbar)`, immediately after the `Toggle Outline` button:

```swift
                Button("Focus Mode") { state.toggleFocusMode() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
```

- [ ] **Step 3: Add the toolbar button**

In `Sources/ReaderMd/Views/Toolbar.swift`, in the View `ToolbarItemGroup(placement: .primaryAction)`, after the outline toggle's closing brace — so the cluster reads reading style → width → outline → focus:

```swift
                    Button { state.toggleFocusMode() } label: {
                        Image(systemName: state.focusMode
                            ? "rectangle.center.inset.filled"
                            : "rectangle.inset.filled")
                    }
                    .dockTooltip("Focus mode (⌥⌘F)")
```

- [ ] **Step 4: Add the palette command**

In `Sources/ReaderMd/Views/QuickOpenView.swift`, in the `cmds` array in `paletteCommands(_:)`, after the `width` command:

```swift
        PaletteCommand(id: "focus", title: "Focus Mode", subtitle: "Layout",
                       systemImage: "rectangle.inset.filled",
                       run: { $0.toggleFocusMode() }),
```

- [ ] **Step 5: Hide the floating close-document button**

`ContentView.swift:83` draws a native ✕ **over** the web view — that is why `diagramFullscreen` had to hide it. Focus mode strips every other piece of chrome and would leave this one button sitting on the page. Replace the condition:

```swift
                if state.selectedFile != nil && !state.diagramFullscreen && !state.focusMode {
```

- [ ] **Step 6: Build and check the whole suite**

Run: `swift build && swift test`
Expected: both pass.

- [ ] **Step 7: Run the app and exercise all four entry points**

Run: `swift run ReaderMd`, open a document, then confirm:
- ⌥⌘F toggles; View ▸ Focus Mode toggles; the toolbar button toggles and its icon changes; ⌘P → `>focus` runs it.
- The floating ✕ disappears in focus mode and comes back on exit.
- Sidebar and outline collapse and are restored on exit, and the canvas narrows and widens back.
- Quit while in focus mode, relaunch: the app opens **not** in focus mode, with the sidebar and canvas width as they were before focus mode was ever entered.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReaderMd/ReaderMdApp.swift Sources/ReaderMd/Views/Toolbar.swift Sources/ReaderMd/Views/QuickOpenView.swift Sources/ReaderMd/ContentView.swift
git commit -m "feat(focus): ⌥⌘F, the View menu item, the toolbar button, and the palette command"
```

---

### Task 5: Fullscreen and toolbar hiding

The riskiest task, and the one with an assumption to confirm before it is committed to. In fullscreen the toolbar is hidden by AppKit, not by us — `.autoHideToolbar` is also what supplies the top-edge hover reveal. With fullscreen switched off there is no OS reveal mechanism and a hand-rolled hover strip is not worth building, so **windowed focus mode hides the toolbar with no reveal**; ⌥⌘F or Esc is the way back. That asymmetry is deliberate.

The presentation options are derived from the "Hide the toolbar" switch, not assumed:

| Fullscreen | Hide toolbar | Behaviour |
| --- | --- | --- |
| on | on | `.autoHideToolbar` + `.autoHideMenuBar`; AppKit hides and reveals on hover. Nothing hidden manually. |
| on | off | `.autoHideMenuBar` only; the toolbar stays visible and the focus button stays clickable. |
| off | on | Hide manually via `documentWindow.toolbar?.isVisible = false`. No reveal. |
| off | off | The toolbar is untouched. |

`NSApp.presentationOptions` is set on the fullscreen-entered notification rather than through `NSWindowDelegate`. SwiftUI owns the window's delegate, and proxying it to add one optional method is more machinery than this needs.

**Files:**
- Modify: `Sources/ReaderMd/Models/AppState.swift`

**Interfaces:**
- Consumes: `AppState.documentWindow`, `focusStash`, and the four switches from Task 1.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Apply the window changes on enter**

In `AppState.swift`, extend `enterFocusMode()` — add after the `if focusNarrowCanvas { … }` line:

```swift
        applyFocusWindowChrome()
```

And add, in the focus mode section:

```swift
    /// The window half of focus mode. In fullscreen it is AppKit that hides the
    /// toolbar — `.autoHideToolbar` is also what supplies the top-edge hover
    /// reveal — so the two switches are not independent.
    ///
    /// Set through `NSApp.presentationOptions` on the fullscreen notification
    /// rather than `NSWindowDelegate`: SwiftUI owns the window's delegate, and
    /// proxying it for one optional method is more machinery than this needs.
    private func applyFocusWindowChrome() {
        guard let window = documentWindow else { return }
        let alreadyFullscreen = window.styleMask.contains(.fullScreen)

        if focusFullscreen && !alreadyFullscreen {
            observeFullScreenEntry()
            window.toggleFullScreen(nil)
        } else if focusFullscreen && alreadyFullscreen {
            applyFullScreenPresentationOptions()
        } else if focusHideToolbar {
            // Windowed: no OS reveal mechanism, so ⌥⌘F or Esc is the way back.
            window.toolbar?.isVisible = false
        }
    }

    private func applyFullScreenPresentationOptions() {
        var options: NSApplication.PresentationOptions = [.autoHideMenuBar]
        if focusHideToolbar { options.insert(.autoHideToolbar) }
        NSApp.presentationOptions = options
    }

    /// `toggleFullScreen` is animated; the presentation options only take once the
    /// window is actually in fullscreen.
    private func observeFullScreenEntry() {
        guard let window = documentWindow else { return }
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window, queue: .main
        ) { [weak self] _ in
            if let token { NotificationCenter.default.removeObserver(token) }
            Task { @MainActor in
                guard let self, self.focusMode else { return }
                self.applyFullScreenPresentationOptions()
            }
        }
    }
```

- [ ] **Step 2: Unwind on exit**

Extend `exitFocusMode()` — add after `focusStash = nil` and before the three restores:

```swift
        restoreWindowChrome(wasAlreadyFullscreen: stash.wasAlreadyFullscreen)
```

Note the ordering: `stash` is read before it is discarded, so keep the existing
`guard let stash = focusStash else { return }` above it. Then add:

```swift
    private func restoreWindowChrome(wasAlreadyFullscreen: Bool) {
        NSApp.presentationOptions = []
        guard let window = documentWindow else { return }
        window.toolbar?.isVisible = true
        // Entering focus mode from a window that was already in fullscreen leaves
        // it there — focus mode did not put it in fullscreen, so it does not take
        // it out.
        if window.styleMask.contains(.fullScreen) && !wasAlreadyFullscreen {
            window.toggleFullScreen(nil)
        }
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds clean. `AppState.swift` already imports `AppKit` for `NSWindow`.

- [ ] **Step 4: Verify the hover reveal against the running app**

This is the assumption the spec flagged. Run `swift run ReaderMd`, open a document, press ⌥⌘F with all four switches at their defaults, then:
- The window enters fullscreen and the toolbar is gone.
- **Move the pointer to the top edge of the screen.** The menu bar and the toolbar should slide down and stay while the pointer is up there.

If the toolbar does **not** reveal, apply the documented fallback: drop `observeFullScreenEntry()` / `applyFullScreenPresentationOptions()`, hide the toolbar manually with `window.toolbar?.isVisible = false` in both configurations, and update the "Hover reveal — fullscreen only" section of `docs/superpowers/specs/2026-08-27-focus-mode-design.md` to say the reveal is unavailable. The mode still works; it loses the mouse-only path out.

- [ ] **Step 5: Verify the rest of the matrix by hand**

Still in the running app, using Settings (Task 6 builds the UI — until then, flip
the switch values in the debugger or temporarily change the `Settings.load…`
defaults):
- Fullscreen **off**, hide toolbar **on**: the window stays put, the toolbar goes, ⌥⌘F brings it back.
- Fullscreen **on**, hide toolbar **off**: fullscreen, toolbar visible, the focus button clickable to exit.
- Enter macOS fullscreen with ⌃⌘F first, **then** ⌥⌘F, then exit focus mode: the window stays in fullscreen (this is `wasAlreadyFullscreen`).
- Esc exits focus mode and unwinds fullscreen.

- [ ] **Step 6: Run the suite**

Run: `swift test`
Expected: PASS. `documentWindow` is nil under test, so `applyFocusWindowChrome()` returns early and Task 1's stash tests are unaffected.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReaderMd/Models/AppState.swift
git commit -m "feat(focus): fullscreen, toolbar hiding, and the hover-reveal presentation options"
```

---

### Task 6: The Settings section

**Files:**
- Modify: `Sources/ReaderMd/Views/SettingsView.swift`

**Interfaces:**
- Consumes: the four switches, their setters, and `focusModeDoesNothing` from Task 1.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Add the section**

In `Sources/ReaderMd/Views/SettingsView.swift`, after the `Section("Reading")` block closes and before `Section("Editing & Export")`:

```swift
            Section("Focus Mode") {
                Toggle("Enter fullscreen", isOn: Binding(
                    get: { state.focusFullscreen },
                    set: { state.setFocusFullscreen($0) }
                ))
                Toggle("Dim other sections", isOn: Binding(
                    get: { state.focusDimSections },
                    set: { state.setFocusDimSections($0) }
                ))
                Toggle("Narrow the canvas", isOn: Binding(
                    get: { state.focusNarrowCanvas },
                    set: { state.setFocusNarrowCanvas($0) }
                ))
                Toggle("Hide the toolbar", isOn: Binding(
                    get: { state.focusHideToolbar },
                    set: { state.setFocusHideToolbar($0) }
                ))

                // Every switch off is allowed rather than forbidden — but ⌥⌘F then
                // does nothing visible, which reads as a broken shortcut without a
                // word of explanation.
                if state.focusModeDoesNothing {
                    Text("With all four off, Focus Mode (⌥⌘F) has no visible effect.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Verify in the app**

Run: `swift run ReaderMd`, press ⌘,:
- The Focus Mode section shows four toggles, all on.
- Switching one off, quitting, and relaunching keeps it off.
- Switching all four off shows the explanatory line; ⌥⌘F then changes nothing on screen.
- With "Dim other sections" off, ⌥⌘F strips the chrome and the page renders normally.

- [ ] **Step 4: Commit**

```bash
git add Sources/ReaderMd/Views/SettingsView.swift
git commit -m "feat(focus): Settings section for the four focus mode switches"
```

---

### Task 7: Documentation

`ShortcutDocTests` fails the build if a shortcut appears in the bundled `SHORTCUTS.md` without a matching row in `docs/features.md`, so steps 1 and 3 must land in the same commit.

**Files:**
- Modify: `Sources/ReaderMd/Resources/docs/SHORTCUTS.md`
- Modify: `Sources/ReaderMd/Resources/docs/CHANGELOG.md`
- Modify: `docs/features.md`
- Modify: `docs/features/reading.md`
- Modify: `docs/features/reading.shots.json`
- Modify: `web/src/data/content.ts`

**Interfaces:**
- Consumes: the finished feature.
- Produces: nothing.

- [ ] **Step 1: Add the shortcut to the bundled list**

In `Sources/ReaderMd/Resources/docs/SHORTCUTS.md`, in the **View** table, after the `⇧⌘\\` row:

```markdown
| ⌥⌘F | Focus Mode (hides the chrome, dims other sections) |
```

- [ ] **Step 2: Add the changelog entry**

In `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, under the section for the next
release (create the `## <version>` heading if the release has not been started —
`release.sh` refuses to publish a version with no section):

```markdown
- **Focus mode** (⌥⌘F) — hides the sidebar, outline and toolbar, goes fullscreen,
  and dims every section but the one you're reading. Each of the four pieces can
  be switched off in Settings; Esc or ⌥⌘F leaves.
```

- [ ] **Step 3: Add the matching row and feature line to `docs/features.md`**

In the **View** shortcut table, after the `⇧⌘\\` row:

```markdown
| ⌥⌘F | Focus Mode (hides the chrome, dims other sections) |
```

And in the one-line-per-feature list, beside the other reading entries:

```markdown
- **Focus mode** — one toggle hides the chrome, goes fullscreen, and dims everything outside the section you're reading.
```

- [ ] **Step 4: Run the doc test**

Run: `swift test --filter ShortcutDocTests`
Expected: PASS. If it fails, the two tables disagree — the token `⌥⌘F` must appear in the first cell of a row in both files.

- [ ] **Step 5: Write the prose**

In `docs/features/reading.md`, add a `## Focus mode` section covering: what ⌥⌘F does, that the toolbar button and ⌘P command do the same, that Esc leaves, that the four pieces are switchable in Settings, and the one asymmetry worth documenting — the top-edge hover reveal exists only when fullscreen is on, because it is AppKit's, and windowed focus mode has no reveal.

Match the voice of the surrounding sections; do not invent behaviour beyond the spec.

- [ ] **Step 6: Capture the screenshot**

Add an entry to `docs/features/reading.shots.json` for a focus mode shot — window size, prefs, the file to open, and the actions to reach the state (open a multi-heading document, scroll to a middle section, press ⌥⌘F).

Then follow the `reader-docs` skill and run its capture harness rather than shooting the screen by hand:

Run: `./scripts/capture.sh docs/features/reading.shots.json`
Expected: the new image lands under `docs/assets/screenshots/reading/`.

- [ ] **Step 7: Add it to the site's shortcut strip**

In `web/src/data/content.ts`, add ⌥⌘F to the compact shortcut strip. The `/docs/` pages are rendered from `docs/*.md` directly, so nothing else in `web/` needs touching.

- [ ] **Step 8: Build the site**

Run: `cd web && npm run build`
Expected: builds clean.

- [ ] **Step 9: Run the whole suite**

Run: `swift test`
Expected: PASS, including `ShortcutDocTests` and `BundledDocTests`.

- [ ] **Step 10: Commit**

```bash
git add Sources/ReaderMd/Resources/docs/SHORTCUTS.md Sources/ReaderMd/Resources/docs/CHANGELOG.md docs/features.md docs/features/reading.md docs/features/reading.shots.json docs/assets/screenshots/reading web/src/data/content.ts
git commit -m "docs: document focus mode across the bundled docs, docs/ and the site"
```

Note: this commit touches `docs/` and `web/`, both Cloudflare Pages build-watch
paths, so merging it to `main` deploys the site with no separate step.
