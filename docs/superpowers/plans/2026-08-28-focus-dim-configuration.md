# Configurable Focus Dimming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn two of focus mode's hardcoded dimming values — the heading level that bounds the lit region, and how dark everything outside it goes — into settings.

**Architecture:** Two new persisted preferences on `AppState` reach the `WKWebView` through the existing `setFocusDim` bridge call, widened from one argument to three. The region depth is an absolute heading level applied as a filter over the boundary list in `applyFocusDim`; the opacity is a CSS custom property. Two new rows in the Settings Form, with a preview flag so the sliders have visible effect while the document window sits behind Settings.

**Tech Stack:** Swift 6.2 / SwiftUI / AppKit, `WKWebView` + plain JS bridge, `XCTest`, `UserDefaults`.

**Spec:** `docs/superpowers/specs/2026-08-28-focus-dim-configuration-design.md`

## Global Constraints

- Deployment target is macOS 13. Any macOS 26-only API needs an availability guard with a pre-26 fallback. Nothing in this plan uses one.
- `Sources/ReaderMd/Models/Settings.swift` owns every `UserDefaults` key and every load/save call. No other file touches `defaults` directly.
- Focus mode preferences load with `defaults.object(forKey:) as? T ?? default`, never `defaults.double`/`defaults.integer` — those return `0` for an absent key, and `0` is a plausible-looking opacity and an invalid depth.
- Opacity clamps to `0.12...0.60` in the setter. It is interpolated into CSS; the clamp is the only guard.
- The default region depth is `.any` and the default opacity is `0.38`, so an existing install sees no behaviour change until it changes a setting.
- New message names crossing JS → Swift must be added to the literal array in `MarkdownWebView.swift`; a `post()` with an unlisted name fails silently. **This plan adds no new message names** — traffic is Swift → JS only.
- Shortcut tables are test-guarded by `ShortcutDocTests`; no shortcut changes here, so that suite should stay green untouched.
- Build: `swift build`. Test: `swift test`. Run: `swift run ReaderMd`.

---

## File Structure

**Modified:**
- `Sources/ReaderMd/Models/Settings.swift` — two new keys and their load/save pairs, beside the four existing focus keys.
- `Sources/ReaderMd/Models/AppState.swift` — the `FocusRegionDepth` enum, two `@Published` properties, two setters, the `focusDimPreview` flag, and the widened `focusDimActive`.
- `Sources/ReaderMd/Views/MarkdownWebView.swift` — the coordinator's `lastFocusDim` cache widens from `Bool?` to a struct; `applyFocusDim` and the `ready` replay carry all three values.
- `Sources/ReaderMd/Resources/web/bridge.js` — `setFocusDim` takes three arguments; `applyFocusDim` filters the boundary list by depth; the comment above it is amended.
- `Sources/ReaderMd/Resources/web/template.html` — the `.focus-dim` rule reads a CSS custom property.
- `Sources/ReaderMd/Views/SettingsView.swift` — two rows in the Focus Mode section, the preview lifecycle, and a taller `minHeight`.
- `Tests/ReaderMdTests/FocusModeTests.swift` — `setUp`/`tearDown` gain the two new keys; new cases for round-trip, clamping, and preview gating.
- `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, `docs/features/reading.md`, `docs/features/settings.md`, `docs/superpowers/specs/2026-08-27-focus-mode-design.md` — prose.
- `docs/assets/screenshots/settings/01-window.png` — re-shot, not edited.

**Created:** none.

---

### Task 1: The model — depth enum, both preferences, and the preview flag

**Files:**
- Modify: `Sources/ReaderMd/Models/Settings.swift:13-16` (keys), `:119-147` (load/save)
- Modify: `Sources/ReaderMd/Models/AppState.swift:205-216` (properties), `:998-1001` (setters)
- Test: `Tests/ReaderMdTests/FocusModeTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `enum FocusRegionDepth: Int, CaseIterable` with cases `h1 = 1, h2 = 2, h3 = 3, any = 4` and `var displayName: String`
  - `AppState.focusRegionDepth: FocusRegionDepth`, `AppState.focusDimOpacity: Double`
  - `AppState.setFocusRegionDepth(_ value: FocusRegionDepth)`, `AppState.setFocusDimOpacity(_ value: Double)`
  - `AppState.focusDimPreview: Bool`
  - `AppState.focusDimActive: Bool` (widened, same name)
  - `Settings.loadFocusRegionDepth() -> FocusRegionDepth`, `Settings.saveFocusRegionDepth(_:)`, `Settings.loadFocusDimOpacity() -> Double`, `Settings.saveFocusDimOpacity(_:)`

- [ ] **Step 1: Extend the test fixture so the suite stays order-independent**

`FocusModeTests` saves and restores every focus key in `setUp`/`tearDown`, because its tests flip switches that persist. Two new keys join that list. In `Tests/ReaderMdTests/FocusModeTests.swift`, add two stored properties beside the existing four:

```swift
    private var savedFocusHideToolbar = true
    private var savedFocusRegionDepth = FocusRegionDepth.any
    private var savedFocusDimOpacity = 0.38
```

In `setUp`, after the existing `savedFocusHideToolbar = Settings.loadFocusHideToolbar()`:

```swift
        savedFocusRegionDepth = Settings.loadFocusRegionDepth()
        savedFocusDimOpacity = Settings.loadFocusDimOpacity()
```

and after the existing `Settings.saveFocusHideToolbar(true)` reset block:

```swift
        Settings.saveFocusRegionDepth(.any)
        Settings.saveFocusDimOpacity(0.38)
```

In `tearDown`, after `Settings.saveFocusHideToolbar(savedFocusHideToolbar)`:

```swift
        Settings.saveFocusRegionDepth(savedFocusRegionDepth)
        Settings.saveFocusDimOpacity(savedFocusDimOpacity)
```

- [ ] **Step 2: Write the failing tests**

Append to `Tests/ReaderMdTests/FocusModeTests.swift`, inside the class:

```swift
    // MARK: - Configurable dimming

    /// Both new preferences default to today's behaviour, so an existing install
    /// sees no change until it touches a setting.
    func testDimmingPreferencesDefaultToTodaysBehaviour() {
        Settings.defaults.removeObject(forKey: "reader.md.focus.regionDepth")
        Settings.defaults.removeObject(forKey: "reader.md.focus.dimOpacity")

        XCTAssertEqual(Settings.loadFocusRegionDepth(), .any)
        XCTAssertEqual(Settings.loadFocusDimOpacity(), 0.38, accuracy: 0.0001)
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
    func testUnknownStoredDepthFallsBackToAny() {
        Settings.defaults.set(99, forKey: "reader.md.focus.regionDepth")

        XCTAssertEqual(Settings.loadFocusRegionDepth(), .any)
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
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift test --filter FocusModeTests`
Expected: FAIL to compile — `cannot find 'FocusRegionDepth' in scope`, `value of type 'AppState' has no member 'focusRegionDepth'`, and similar for `focusDimOpacity`, `focusDimPreview`, and the four `Settings` functions.

- [ ] **Step 4: Make `Settings.defaults` reachable from the tests**

The tests above call `Settings.defaults.removeObject(...)` to exercise the absent-key path, and the declaration is `private`, which `@testable import` cannot reach. In `Sources/ReaderMd/Models/Settings.swift:28`, drop the keyword:

```swift
    static var defaults: UserDefaults { .standard }
```

`@testable import` raises `internal` to visible; it does not raise `private`. This is the whole change — no other access level moves.

- [ ] **Step 5: Add the two keys and their load/save pairs**

In `Sources/ReaderMd/Models/Settings.swift`, after `focusHideToolbarKey` (line 16):

```swift
    private static let focusRegionDepthKey = "reader.md.focus.regionDepth"
    private static let focusDimOpacityKey = "reader.md.focus.dimOpacity"
```

After `saveFocusHideToolbar` (around line 147):

```swift
    // Both default to what focus mode shipped with, so an existing install sees
    // no change until it touches a setting. `object(forKey:) as?` rather than
    // `integer`/`double`: those return 0 for an absent key, and 0 is neither a
    // valid heading level nor a legible opacity.
    static func loadFocusRegionDepth() -> FocusRegionDepth {
        guard let raw = defaults.object(forKey: focusRegionDepthKey) as? Int,
              let depth = FocusRegionDepth(rawValue: raw) else { return .any }
        return depth
    }
    static func saveFocusRegionDepth(_ value: FocusRegionDepth) {
        defaults.set(value.rawValue, forKey: focusRegionDepthKey)
    }

    static func loadFocusDimOpacity() -> Double {
        defaults.object(forKey: focusDimOpacityKey) as? Double ?? 0.38
    }
    static func saveFocusDimOpacity(_ value: Double) {
        defaults.set(value, forKey: focusDimOpacityKey)
    }
```

- [ ] **Step 6: Add the depth enum**

In `Sources/ReaderMd/Models/AppState.swift`, beside the other module-scope enums (after `ContentWidth`, which ends around line 95):

```swift
/// The deepest heading level that ends a focus mode dim region.
///
/// Deliberately an ABSOLUTE level, not one relative to the active heading. The
/// relative rule — "the next heading of the same or higher level" — was rejected
/// in the original focus mode design: with `h2 A / h3 A.1 / h2 B` it makes a
/// ~20px scroll swing the lit region between one paragraph and the whole of A.
/// An absolute level changes the region only when a boundary heading is crossed,
/// and at `.h2` the `h3` is not a boundary at all.
enum FocusRegionDepth: Int, CaseIterable {
    case h1 = 1, h2 = 2, h3 = 3, any = 4

    var displayName: String {
        switch self {
        case .any: return "Any heading"
        case .h3:  return "H3 or above"
        case .h2:  return "H2 or above"
        case .h1:  return "H1 only"
        }
    }
}
```

Note the case order in `allCases` is `h1, h2, h3, any`; the Settings picker in Task 3 lists them deliberately in the reverse of that, widest region last.

- [ ] **Step 7: Add the properties, the preview flag, and the widened `focusDimActive`**

In `Sources/ReaderMd/Models/AppState.swift`, replace lines 209-215 (the four switches plus `focusDimActive`) with:

```swift
    @Published var focusFullscreen: Bool = Settings.loadFocusFullscreen()
    @Published var focusDimSections: Bool = Settings.loadFocusDimSections()
    @Published var focusNarrowCanvas: Bool = Settings.loadFocusNarrowCanvas()
    @Published var focusHideToolbar: Bool = Settings.loadFocusHideToolbar()

    @Published var focusRegionDepth: FocusRegionDepth = Settings.loadFocusRegionDepth()
    @Published var focusDimOpacity: Double = Settings.loadFocusDimOpacity()

    /// True while the Settings window is open, so the two dimming controls have
    /// visible effect on the document behind it. Widens what counts as "dimming
    /// is showing" — never what counts as "focus mode is on", which is why
    /// `focusMode` itself is untouched by it.
    @Published var focusDimPreview: Bool = false

    /// What the web view is told. Dimming needs both the mode and its switch.
    var focusDimActive: Bool { (focusMode || focusDimPreview) && focusDimSections }
```

- [ ] **Step 8: Add the two setters**

In `Sources/ReaderMd/Models/AppState.swift`, after `setFocusDimSections` (line 1001):

```swift
    func setFocusRegionDepth(_ value: FocusRegionDepth) {
        focusRegionDepth = value
        Settings.saveFocusRegionDepth(value)
    }

    /// Clamped because the value is interpolated straight into a CSS custom
    /// property: above .60 dimming stops reading as dimming, below .12 a glance
    /// back at the previous section stops being possible.
    func setFocusDimOpacity(_ value: Double) {
        focusDimOpacity = min(max(value, 0.12), 0.60)
        Settings.saveFocusDimOpacity(focusDimOpacity)
    }
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `swift test --filter FocusModeTests`
Expected: PASS, including the pre-existing stash tests.

- [ ] **Step 10: Run the whole suite**

Run: `swift test`
Expected: PASS. `ShortcutDocTests` in particular should be untouched — no shortcut changed.

- [ ] **Step 11: Commit**

```bash
git add Sources/ReaderMd/Models/Settings.swift Sources/ReaderMd/Models/AppState.swift Tests/ReaderMdTests/FocusModeTests.swift
git commit -m "feat(focus): region depth and dim opacity preferences"
```

---

### Task 2: The bridge — depth filter and the opacity custom property

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/bridge.js:111-114` (`setFocusDim`), `:649-679` (`applyFocusDim` and its comment)
- Modify: `Sources/ReaderMd/Resources/web/template.html:272-276` (the `.focus-dim` rule)
- Modify: `Sources/ReaderMd/Views/MarkdownWebView.swift:127` (call site), `:215` (cache), `:291-296` (`applyFocusDim`), `:681` (`ready` replay)

**Interfaces:**
- Consumes: `AppState.focusDimActive`, `AppState.focusDimOpacity`, `AppState.focusRegionDepth` from Task 1.
- Produces:
  - JS: `window.ReaderMd.setFocusDim(on, opacity, depth)` — `on: boolean`, `opacity: number`, `depth: number` (1–4)
  - Swift: `Coordinator.applyFocusDim(_ on: Bool, opacity: Double, depth: Int)` and a private `struct FocusDimState: Equatable { var on: Bool; var opacity: Double; var depth: Int }`

- [ ] **Step 1: Make the CSS rule read a custom property**

In `Sources/ReaderMd/Resources/web/template.html`, replace lines 272-276:

```css
    /* Focus mode: everything outside the current heading's region. Dimmed, not
       hidden — the default .38 stays legible, so glancing back at the previous
       section does not require leaving the mode. The custom property is set by
       setFocusDim(); the fallback keeps the rule correct if it is ever unset. */
    .focus-dim { opacity: var(--focus-dim-opacity, .38); transition: opacity .2s ease; }
```

- [ ] **Step 2: Widen the JS setter**

In `Sources/ReaderMd/Resources/web/bridge.js`, replace `setFocusDim` (lines 111-114):

```js
  setFocusDim(on, opacity, depth) {
    focusDim = on;
    focusDepth = depth;
    document.documentElement.style.setProperty('--focus-dim-opacity', opacity);
    applyFocusDim();
  },
```

- [ ] **Step 3: Add the depth variable and filter the boundary list**

In `Sources/ReaderMd/Resources/web/bridge.js`, replace line 649:

```js
let focusDim = false;
// The deepest heading level that ends a region; 4 = every heading, the default.
let focusDepth = 4;
```

Then amend the comment above `applyFocusDim` (lines 651-655) and the boundary scan inside it. The comment currently asserts the region ends at the next heading of any level and argues why; it must now explain the depth filter and why an absolute level does not reintroduce what it argues against:

```js
// Classes the top-level blocks OUTSIDE the active heading's region. Deliberately
// no <section> wrappers: marked emits a flat h2/p/p/h2 sibling list, and mark
// anchoring, find, footnotes and diff hunks all read that flat structure.
//
// The region ends at the next heading at or above `focusDepth` — every heading
// by default. Depth is an ABSOLUTE level, fixed by the setting, never one
// relative to the active heading. The relative rule ("the next heading of the
// same or higher level") would make a 20px scroll across a nested heading swing
// the lit region between a paragraph and its whole parent section; an absolute
// level changes the region only when a boundary heading is crossed, and a
// heading deeper than the setting is not a boundary at all.
function applyFocusDim() {
  const blocks = [...contentEl.children];
  for (const b of blocks) b.classList.remove('focus-dim');

  // Suspended while a search is active (a match inside a dimmed section is hard
  // to spot) and in diff mode (the spy tracks hunks, and the layout is
  // side-by-side).
  if (!focusDim || diffMode || findQuery) return;

  const headings = [];
  blocks.forEach((b, i) => {
    if (/^H[1-4]$/.test(b.tagName) && +b.tagName[1] <= focusDepth) headings.push(i);
  });
  // One region means dimming has nothing to say. Also the answer when every
  // heading in the document is deeper than the chosen depth: no boundaries, so
  // no regions to tell apart.
  if (headings.length < 2) return;
```

Leave the rest of the function (the ≤100px active scan, the `next` lookup, the classing pass) exactly as it is.

- [ ] **Step 4: Verify `reportActiveHeading` was not touched**

Depth must not reach the outline's active-row highlight — the outline highlights the heading you are actually under, at every level, regardless of how wide the lit region is.

Run: `grep -n "focusDepth" Sources/ReaderMd/Resources/web/bridge.js`
Expected: exactly three hits — the `let` declaration, the assignment in `setFocusDim`, and the filter in `applyFocusDim`. If a fourth appears inside `reportActiveHeading`, remove it.

- [ ] **Step 5: Widen the coordinator's cache**

In `Sources/ReaderMd/Views/MarkdownWebView.swift`, replace line 215:

```swift
        private var lastFocusDim: FocusDimState?
```

and add the type beside it (inside the `Coordinator` class):

```swift
        /// All three values the web view needs, cached together. As a bare `Bool`
        /// this swallowed opacity and depth changes whenever `on` was unchanged.
        private struct FocusDimState: Equatable {
            var on: Bool
            var opacity: Double
            var depth: Int
        }
```

- [ ] **Step 6: Widen `applyFocusDim` and the `ready` replay**

Replace `applyFocusDim` (lines 291-296):

```swift
        func applyFocusDim(_ on: Bool, opacity: Double, depth: Int) {
            let next = FocusDimState(on: on, opacity: opacity, depth: depth)
            guard isReady else { lastFocusDim = next; return }
            guard lastFocusDim != next else { return }
            lastFocusDim = next
            pushFocusDim(next)
        }

        private func pushFocusDim(_ s: FocusDimState) {
            webView?.evaluateJavaScript(
                "window.ReaderMd.setFocusDim(\(s.on), \(s.opacity), \(s.depth));")
        }
```

Replace line 681 (inside the `ready` case):

```swift
                if let dim = lastFocusDim { pushFocusDim(dim) }
```

- [ ] **Step 7: Update the call site**

Replace line 127 in `updateNSView`:

```swift
        coord.applyFocusDim(state.focusDimActive,
                            opacity: state.focusDimOpacity,
                            depth: state.focusRegionDepth.rawValue)
```

- [ ] **Step 8: Build**

Run: `swift build`
Expected: succeeds with no warnings from the touched files.

- [ ] **Step 9: Verify the region logic in the running app**

The region walk is JavaScript inside a `WKWebView` and is not reachable from `swift test`, so it is verified by running the app. There is no Settings UI yet (Task 3), so drive it from the defaults first:

```bash
defaults write com.readermd.ReaderMd reader.md.focus.regionDepth -int 2
swift run ReaderMd
```

Open a document with nested headings — `docs/features/reading.md` has `##` and `###` — and press ⌥⌘F. Confirm: the lit region spans a whole `##` section **including** its `###` subheadings, and scrolling across a `###` inside it changes nothing. Then:

```bash
defaults write com.readermd.ReaderMd reader.md.focus.dimOpacity -float 0.15
```

Relaunch, ⌥⌘F, and confirm the dimmed text is visibly darker than before. Finally check the degenerate case: a document whose headings are all `###` at depth 2 should show **no** dimming at all rather than dimming everything.

Reset when done:

```bash
defaults delete com.readermd.ReaderMd reader.md.focus.regionDepth
defaults delete com.readermd.ReaderMd reader.md.focus.dimOpacity
```

If the bundle id above is wrong, read it from `make-app.sh` (`grep -i bundleidentifier make-app.sh`) — under `swift run` the domain may differ; `defaults domains | tr ',' '\n' | grep -i reader` will find it.

- [ ] **Step 10: Run the suite**

Run: `swift test`
Expected: PASS — Task 1's tests still green, nothing here changes Swift-visible behaviour.

- [ ] **Step 11: Commit**

```bash
git add Sources/ReaderMd/Resources/web/bridge.js Sources/ReaderMd/Resources/web/template.html Sources/ReaderMd/Views/MarkdownWebView.swift
git commit -m "feat(focus): apply region depth and dim opacity in the web view"
```

---

### Task 3: The Settings rows and the preview lifecycle

**Files:**
- Modify: `Sources/ReaderMd/Views/SettingsView.swift:60-85` (the Focus Mode section), `:118` (the `.frame` modifier)

**Interfaces:**
- Consumes: `AppState.focusRegionDepth`, `AppState.focusDimOpacity`, `AppState.focusDimPreview`, `AppState.setFocusRegionDepth`, `AppState.setFocusDimOpacity`, `FocusRegionDepth.displayName`, `FocusRegionDepth.allCases` from Task 1; the live bridge from Task 2.
- Produces: nothing consumed by a later task.

- [ ] **Step 1: Add the two rows**

In `Sources/ReaderMd/Views/SettingsView.swift`, inside `Section("Focus Mode")`, after the `Toggle("Dim other sections", …)` and before `Toggle("Narrow the canvas", …)`:

```swift
                // Both indented under the switch they depend on, and disabled with
                // it: with dimming off they have nothing to act on, and greying
                // them says so without hiding them.
                Picker("Region ends at", selection: Binding(
                    get: { state.focusRegionDepth },
                    set: { state.setFocusRegionDepth($0) }
                )) {
                    // Widest region last, so the list reads tightest → loosest.
                    // That is the reverse of `allCases`, hence the explicit order.
                    ForEach([FocusRegionDepth.any, .h3, .h2, .h1], id: \.self) { depth in
                        Text(depth.displayName).tag(depth)
                    }
                }
                .disabled(!state.focusDimSections)

                // Bound to STRENGTH, not opacity, so dragging right dims more —
                // the direction the label implies. Range 40%–88% in steps of 2%
                // is opacity .60 down to .12 in steps of .02.
                LabeledContent("Dimming") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { 1 - state.focusDimOpacity },
                                set: { state.setFocusDimOpacity(1 - $0) }
                            ),
                            in: 0.40...0.88, step: 0.02
                        )
                        Text("\(Int(((1 - state.focusDimOpacity) * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!state.focusDimSections)
```

- [ ] **Step 2: Add the preview lifecycle**

On the `Form` in `SettingsView`, beside the existing `.formStyle(.grouped)`:

```swift
        // Dimming renders only while focus mode is running, and these controls
        // live in a different window — so without this the slider has no visible
        // effect at the moment you are dragging it. The document window behind
        // Settings dims at the current values instead, and stops when it closes.
        .onAppear { state.focusDimPreview = true }
        .onDisappear { state.focusDimPreview = false }
```

- [ ] **Step 3: Raise the minimum height**

The `Settings` scene's `NSWindow` autosaves its frame under a fixed key, so a window last closed before the section grew reopens at the old height and clips the bottom of the form. Two rows were added. Replace line 118:

```swift
        .frame(minWidth: 420, maxWidth: 420, minHeight: 760)
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: succeeds.

- [ ] **Step 5: Verify in the running app**

Run: `swift run ReaderMd`

Then, with a document open:

1. Press ⌘, — the Settings window opens and the **document behind it dims**, since the preview flag is on.
2. Drag **Dimming**: the document updates live, and the readout tracks it. Confirm right = darker.
3. Change **Region ends at** to *H2 or above*: the lit region on the document widens to include subheadings.
4. Confirm the whole form is visible — the **Editing & Export** section must not be clipped at the bottom of the window. If it is, raise `minHeight` further.
5. Uncheck **Dim other sections**: both new rows grey out, and the document stops dimming.
6. Close Settings: the document returns to full brightness, and `⌥⌘F` still enters and leaves focus mode normally.
7. Re-open Settings **while focus mode is on** and drag the slider: it still updates, and closing Settings does **not** exit focus mode or undim.

Then check the autosaved-frame trap directly, since that is the most likely thing to ship broken:

```bash
defaults delete com.readermd.ReaderMd "NSWindow Frame com_apple_SwiftUI_Settings_window"
```

Relaunch, press ⌘,, and confirm the window opens tall enough. (If that key does not exist, list the candidates with `defaults read com.readermd.ReaderMd | grep -i "NSWindow Frame"`.)

- [ ] **Step 6: Run the suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReaderMd/Views/SettingsView.swift
git commit -m "feat(focus): Settings rows for region depth and dim strength"
```

---

### Task 4: Documentation and the re-shot screenshot

**Files:**
- Modify: `Sources/ReaderMd/Resources/docs/CHANGELOG.md:9-15`
- Modify: `docs/features/reading.md:91-94`
- Modify: `docs/features/settings.md`
- Modify: `docs/superpowers/specs/2026-08-27-focus-mode-design.md` (the "What 'current' means" section)
- Modify: `docs/assets/screenshots/settings/01-window.png` (re-shot from `docs/features/settings.shots.json`)

**Interfaces:**
- Consumes: the shipped behaviour from Tasks 1–3.
- Produces: nothing consumed by a later task.

None of this prose is test-guarded — `ShortcutDocTests` only checks that shortcuts appear in both places, and no shortcut changed here. It drifts silently if skipped.

- [ ] **Step 1: Extend the changelog entry**

Focus mode is still under `## [Unreleased]` and unreleased, so this extends the existing bullet rather than adding a second one. In `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, append to the **Focus mode** bullet:

```markdown
  Settings also sets how wide the lit region is — every heading, or only
  headings down to H3, H2 or H1, so a section keeps its subsections lit — and
  how far the rest dims.
```

- [ ] **Step 2: Update the reading page**

In `docs/features/reading.md`, replace the dimming paragraph (lines 91-94):

```markdown
The dimming follows the outline rather than the scroll position, so it holds
still while you read a section and fades across when you reach the next
heading. **Region ends at** in Settings decides how wide "a section" is: every
heading by default, or only headings down to H3, H2 or H1 — at *H2 or above* an
`h2` stays lit across all of its subheadings, and crossing one of them changes
nothing. A document whose headings are all deeper than that setting has no
regions to tell apart, so nothing dims. **Dimming** sets how far the rest fades,
from 40% to 88%. Dimming steps aside entirely while you're searching, in diff
mode, and in a document with fewer than two headings.
```

- [ ] **Step 3: Fix the Settings page**

`docs/features/settings.md` still describes the window as three sections and never got a Focus Mode section — drift that arrived with focus mode itself, and the two new rows land in the section it is missing.

Replace the sentence in the opening paragraph:

```markdown
Settings (⌘,) collects every preference in one window, grouped the way you would
look for them: **Appearance**, **Reading**, **Focus Mode**, and
**Editing & Export**.
```

Then add a section immediately before `## Editing and export` (line 58 — note the page's own heading is "Editing and export", not "Editing & Export"):

```markdown
## Focus Mode

Focus mode (⌥⌘F) is four things at once, and each is a switch here: **Enter
fullscreen**, **Dim other sections**, **Narrow the canvas**, and **Hide the
toolbar**. All four are on by default. Turning all four off leaves ⌥⌘F with
nothing to do, and the window says so.

Two settings shape the dimming itself. **Region ends at** decides how much of
the document counts as the section you're reading: *Any heading* is the default
and lights one heading's worth at a time, while *H2 or above* keeps a whole `h2`
section lit including its subheadings. **Dimming** sets how far everything else
fades, from 40% to 88%.

Both only matter with **Dim other sections** on, and grey out without it. While
this window is open the document behind it previews them, so dragging the slider
shows you the result.
```

- [ ] **Step 4: Point the old spec at the new one**

In `docs/superpowers/specs/2026-08-27-focus-mode-design.md`, at the end of the "What 'current' means" section, add:

```markdown
**Superseded in part:** the region's end is now a setting — see
`2026-08-28-focus-dim-configuration-design.md`. The argument above still stands
and is why that setting is an *absolute* heading level rather than the relative
"same or higher" rule rejected here.
```

- [ ] **Step 5: Re-shoot the Settings screenshot**

The shot shows the whole Settings window, which gained two rows. Re-run the manifest rather than editing the image.

Invoke the `reader-docs` skill and follow it; the manifest is `docs/features/settings.shots.json` and the shot to refresh is `01-window`. Do not hand-edit `docs/assets/screenshots/settings/01-window.png`.

- [ ] **Step 6: Confirm the docs suite is still green**

Run: `swift test --filter ShortcutDocTests`
Expected: PASS. Also run `swift test --filter BundledDocTests`; the changelog is bundled into the app, so a malformed edit surfaces there.

- [ ] **Step 7: Commit**

```bash
git add Sources/ReaderMd/Resources/docs/CHANGELOG.md docs/features/reading.md docs/features/settings.md docs/superpowers/specs/2026-08-27-focus-mode-design.md docs/assets/screenshots/settings/01-window.png
git commit -m "docs(focus): document configurable region depth and dim strength"
```

---

## Done when

- `swift test` passes.
- ⌘, shows **Region ends at** and **Dimming**, both greyed with **Dim other sections** off, and the whole form is visible in a window whose saved frame predates them.
- At *H2 or above*, scrolling across an `h3` inside an `h2` changes nothing on screen.
- A document whose headings are all deeper than the chosen depth shows no dimming rather than dimming everything.
- Dragging **Dimming** with Settings open changes the document behind it, and closing Settings clears that without touching focus mode.
- `docs/features/settings.md` describes the Focus Mode section, and its screenshot shows the two new rows.
