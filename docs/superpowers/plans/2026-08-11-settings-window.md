# Settings Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native ⌘, Settings window that consolidates Reader.md's six persisted preferences into one place.

**Architecture:** A `SwiftUI.Settings` scene sibling to the existing `WindowGroup`, holding a single grouped `Form` bound to the `AppState` setters that already exist. One preference (PDF export layout) gains an `AppState` owner on the way in. Because this is the app's first second window, the global ⌘W key monitor and the `File ▸ Close` retarget both need to learn which window is the document window.

**Tech Stack:** Swift 6.2 / SwiftUI / AppKit, SwiftPM, XCTest. macOS 13 deployment target, Xcode 26 / macOS 26 SDK toolchain.

**Spec:** `docs/superpowers/specs/2026-08-11-settings-window-design.md`

## Global Constraints

- Deployment target is **macOS 13**. Any macOS 26-only API needs an `if #available(macOS 26.0, *)` guard with a pre-26 fallback. Nothing in this plan needs one — `Form`, `.formStyle(.grouped)`, `Settings`, and `Slider` are all macOS 13.
- Write **`SwiftUI.Settings`**, never bare `Settings`, for the scene. `Sources/ReaderMd/Models/Settings.swift` declares a module-scope `enum Settings` that shadows it. Do **not** rename the enum.
- Every preference write goes `control → AppState.setX() → @Published mutation → Settings.saveX()`. No view and no coordinator touches `UserDefaults` or `Settings.*` directly.
- `AppState` is `@MainActor`. Tests that touch it are marked `@MainActor` (see `Tests/ReaderMdTests/EditableFileTests.swift:8`).
- Tests that mutate `UserDefaults` must save the prior value and restore it in a `defer`, following `EditableFileTests.swift:69-80`.
- Nothing existing is removed: every toolbar control, `File ▸ Set Default Editor…`, and the ⌘E save panel's layout popup all stay.
- Build with `swift build`. Run tests with `swift test`. Run the app with `swift run ReaderMd`.
- Do **not** touch `web/` in any commit in this plan. A push to `main` touching `web/` deploys the site immediately; that edit belongs to the release commit.
- Commit messages follow the repo's Conventional Commits style (`feat(scope):`, `fix(scope):`, `docs(scope):`) and end with:

  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  ```

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/ReaderMd/Models/AppState.swift` | *modify* — gains `exportLayout` + `setExportLayout`, `setTheme`, `clearEditor`, and a weak `documentWindow` |
| `Sources/ReaderMd/Views/MarkdownWebView.swift` | *modify* — save panel seeds from `state.exportLayout` and stops writing it back |
| `Sources/ReaderMd/Views/WindowAccessor.swift` | *create* — one `NSViewRepresentable` that hands `ContentView`'s `NSWindow` to `AppState` |
| `Sources/ReaderMd/ContentView.swift` | *modify* — attaches `WindowAccessor` |
| `Sources/ReaderMd/ReaderMdApp.swift` | *modify* — the `SwiftUI.Settings` scene, plus the key-window fixes in `AppDelegate` |
| `Sources/ReaderMd/Views/SettingsView.swift` | *create* — the `Form`, and nothing else |
| `Tests/ReaderMdTests/ExportLayoutTests.swift` | *modify* — adds the `AppState` ownership round-trip |
| `Tests/ReaderMdTests/EditableFileTests.swift` | *modify* — adds the `clearEditor` test |
| `Sources/ReaderMd/Resources/docs/SHORTCUTS.md`, `CHANGELOG.md`, `docs/features.md` | *modify* — user-facing docs |

Tasks are ordered so each one builds and tests green on its own. Task 2 is the risky one and is deliberately isolated from the UI work.

---

### Task 1: Move `exportLayout` onto `AppState`

The save panel's layout popup currently reads and writes `UserDefaults` directly (`MarkdownWebView.swift:492` and `:503`), with no in-memory owner. The Settings window needs something to bind to. On the way, the write-back goes: picking "Continuous" for one export must stop silently changing the default.

**Files:**
- Modify: `Sources/ReaderMd/Models/AppState.swift` (`@Published` block near `:235`, `init` near `:334`, and a new setter beside `setContentWidth` at `:751`)
- Modify: `Sources/ReaderMd/Views/MarkdownWebView.swift:492`, `:501-503`
- Test: `Tests/ReaderMdTests/ExportLayoutTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `AppState.exportLayout: ExportLayout` — `@Published private(set)`
  - `AppState.setExportLayout(_ value: ExportLayout)` — mutates and persists

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ReaderMdTests/ExportLayoutTests.swift`, inside the existing `final class ExportLayoutTests: XCTestCase` (before its closing brace). Add `@MainActor` to each new test rather than the class — the four existing tests are not `@MainActor` and marking the class would be a wider change than needed:

```swift
    /// AppState is the single in-memory owner: it seeds from the persisted
    /// value at launch, and setting it writes straight through.
    @MainActor
    func testAppStateSeedsFromPersistedLayout() {
        let saved = Settings.loadExportLayout()
        defer { Settings.saveExportLayout(saved) }

        Settings.saveExportLayout(.continuous)
        XCTAssertEqual(AppState().exportLayout, .continuous)
    }

    @MainActor
    func testSetExportLayoutPersists() {
        let saved = Settings.loadExportLayout()
        defer { Settings.saveExportLayout(saved) }

        let state = AppState()
        state.setExportLayout(.continuous)
        XCTAssertEqual(state.exportLayout, .continuous)
        XCTAssertEqual(Settings.loadExportLayout(), .continuous)
        // A fresh state sees it too — the write reached UserDefaults, not just memory.
        XCTAssertEqual(AppState().exportLayout, .continuous)
    }

    /// The ⌘E save panel's popup is a per-export override. Choosing the other
    /// layout for one export must not move the stored default — which is what
    /// the panel used to do, straight to UserDefaults.
    @MainActor
    func testALocalLayoutChoiceDoesNotMoveTheDefault() {
        let saved = Settings.loadExportLayout()
        defer { Settings.saveExportLayout(saved) }

        Settings.saveExportLayout(.pageByPage)
        let state = AppState()

        // Exactly what presentExportPanel does with the popup's selection:
        // read it, use it, and never write it back.
        let picked = ExportLayout.allCases[1]
        XCTAssertEqual(picked, .continuous)

        XCTAssertEqual(state.exportLayout, .pageByPage)
        XCTAssertEqual(Settings.loadExportLayout(), .pageByPage)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter ExportLayoutTests
```

Expected: FAIL — compile error, `value of type 'AppState' has no member 'exportLayout'`.

- [ ] **Step 3: Add the property, the seed, and the setter**

In `Sources/ReaderMd/Models/AppState.swift`, add the property beside the other view preferences (immediately after `@Published var contentWidth: ContentWidth = .wide` at `:194`):

```swift
    /// Default layout for ⌘E. The save panel's popup seeds from this and is a
    /// per-export override — it deliberately does not write back, or a one-off
    /// Continuous export would silently become the default.
    @Published private(set) var exportLayout: ExportLayout = .pageByPage
```

In `init`, add the seed immediately after `contentWidth = Settings.loadContentWidth()` (`:324`):

```swift
        exportLayout = Settings.loadExportLayout()
```

Add the setter immediately after `setContentWidth(_:)` ends at `:754`, before `cycleContentWidth()`:

```swift
    func setExportLayout(_ value: ExportLayout) {
        exportLayout = value
        Settings.saveExportLayout(value)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter ExportLayoutTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Point the save panel at `AppState`**

In `Sources/ReaderMd/Views/MarkdownWebView.swift`, the coordinator already holds `var state: AppState` (assigned in `updateNSView` at `:122`), so `presentExportPanel()` can read it directly.

Replace line `:492`:

```swift
            picker.selectItem(at: ExportLayout.allCases.firstIndex(of: Settings.loadExportLayout()) ?? 0)
```

with:

```swift
            picker.selectItem(at: ExportLayout.allCases.firstIndex(of: state.exportLayout) ?? 0)
```

Then delete the write-back at `:503` — the line `Settings.saveExportLayout(layout)` — and update the comment above `:501` so it explains the new contract. The block at `:501-503` becomes:

```swift
            guard panel.runModal() == .OK, let url = panel.url else { return }
            // Per-export override, not a preference write: the default lives in
            // Settings ▸ Editing & Export. Persisting here meant one Continuous
            // export quietly changed every later export.
            let layout = ExportLayout.allCases[picker.indexOfSelectedItem]
```

- [ ] **Step 6: Verify it still builds and every test passes**

```bash
swift build && swift test
```

Expected: build succeeds; all tests pass.

- [ ] **Step 7: Verify the behavior change by hand**

```bash
swift run ReaderMd
```

Open any markdown file, press ⌘E, switch the Layout popup to "Continuous", save the PDF. Press ⌘E again — the popup must read **"Page by Page"**, not "Continuous". (Before this change it would have remembered "Continuous".)

- [ ] **Step 8: Commit**

```bash
git add Sources/ReaderMd/Models/AppState.swift Sources/ReaderMd/Views/MarkdownWebView.swift Tests/ReaderMdTests/ExportLayoutTests.swift
git commit -m "$(cat <<'EOF'
refactor(export): give the PDF layout preference an AppState owner

The save panel read and wrote UserDefaults directly, so picking Continuous
for a single export silently became the default for every later one. The
popup now seeds from AppState and is a per-export override; the stored
default only moves from Settings.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Teach ⌘W and `File ▸ Close` which window is the document

This is the prerequisite for a second window and has no relationship to the Settings UI, so it lands on its own. `AppDelegate` installs a global key monitor (`ReaderMdApp.swift:215`) that swallows ⌘W and calls `closeFileOrQuit`, guarded only on "no modal, no sheet". A Settings window is neither — so once Task 3 adds one, ⌘W with Settings focused would close your *document*, or pop the quit alert. `retargetCloseItem()` (`:237`) rewrites `File ▸ Close` and has the same hole.

**Files:**
- Create: `Sources/ReaderMd/Views/WindowAccessor.swift`
- Modify: `Sources/ReaderMd/Models/AppState.swift` (one weak property)
- Modify: `Sources/ReaderMd/ContentView.swift:32`
- Modify: `Sources/ReaderMd/ReaderMdApp.swift:215-245`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces:
  - `AppState.documentWindow: NSWindow?` — `weak var`, **not** `@Published`
  - `struct WindowAccessor: NSViewRepresentable` — takes `onWindow: (NSWindow) -> Void`

- [ ] **Step 1: Add the weak property to `AppState`**

There is no unit test for this task — every part of it is AppKit window and menu behavior, which `swift test` cannot reach (`swift test` is pure logic only, per `CLAUDE.md`). Step 7 is the verification and it is not optional.

In `Sources/ReaderMd/Models/AppState.swift`, add immediately after `@Published var sidebarWidth: Double = 260` (`:198`):

```swift
    /// The WindowGroup's window, tagged by `WindowAccessor` on ContentView.
    /// Deliberately not @Published — nothing renders from it, and republishing
    /// on every window change would churn the view tree. Weak so closing the
    /// window doesn't keep it alive.
    ///
    /// AppDelegate's ⌘W monitor uses it to tell the document window apart from
    /// the Settings window; a nil value means "don't intercept", which is the
    /// safe direction.
    weak var documentWindow: NSWindow?
```

- [ ] **Step 2: Create `WindowAccessor`**

Create `Sources/ReaderMd/Views/WindowAccessor.swift`:

```swift
import SwiftUI
import AppKit

/// Hands the hosting `NSWindow` back to SwiftUI. Reader.md uses it to tell its
/// document window apart from the Settings window, which AppKit-level code
/// (the ⌘W key monitor) can't do from a SwiftUI view hierarchy alone.
///
/// The lookup is deferred: `makeNSView` runs before the view is in a window, so
/// `view.window` is nil there. Same tick-later pattern as the ⌘F focus grab
/// (`Toolbar.swift`) and the export panel (`MarkdownWebView.swift`).
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    /// Re-reports on every update: a window can be torn down and rebuilt (a
    /// restored session, a closed-then-reopened window) and the weak reference
    /// on the other end would be nil after that.
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
    }
}
```

- [ ] **Step 3: Attach it to `ContentView`**

In `Sources/ReaderMd/ContentView.swift`, the body already carries `.background(findStepShortcuts)` at `:32`. Add directly beneath it:

```swift
        .background(WindowAccessor { state.documentWindow = $0 })
```

- [ ] **Step 4: Guard the ⌘W monitor**

In `Sources/ReaderMd/ReaderMdApp.swift`, the monitor's `guard` currently reads (`:216-222`):

```swift
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w",
                  // A sheet or the quit alert is already up: leave ⌘W alone, or repeat
                  // presses stack a second alert on top of the first.
                  NSApp.modalWindow == nil, NSApp.keyWindow?.sheets.isEmpty ?? true,
                  let self
            else { return event }
```

Add one condition, so the whole guard becomes:

```swift
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w",
                  // A sheet or the quit alert is already up: leave ⌘W alone, or repeat
                  // presses stack a second alert on top of the first.
                  NSApp.modalWindow == nil, NSApp.keyWindow?.sheets.isEmpty ?? true,
                  let self,
                  // Only the document window closes documents. Settings (and any
                  // future window) gets AppKit's performClose. Fails closed while
                  // documentWindow is still nil, one tick after launch.
                  MainActor.assumeIsolated({
                      guard let doc = self.state?.documentWindow else { return false }
                      return NSApp.keyWindow === doc
                  })
            else { return event }
```

`MainActor.assumeIsolated` is required because the monitor's closure is not main-actor isolated but `AppState` is — the same call already appears at `ReaderMdApp.swift:233`. The monitor only ever fires on the main thread, which is what makes the assumption sound.

The closure returns a `Bool`, not the window: `assumeIsolated` constrains its return type to `Sendable`, and `NSWindow` is not. Comparing inside and handing back the answer sidesteps that.

- [ ] **Step 5: Make `retargetCloseItem()` restore rather than bail**

This is the subtle half. `retargetCloseItem()` **mutates a persistent menu item**, and the assignment sticks. An early `return` when Settings is key would leave `File ▸ Close` still pointing at `closeFileOrQuit` from the last time the document window was focused — reproducing the exact bug through the menu instead of the key equivalent. The non-document branch has to actively put `performClose` back.

Replace the whole of `retargetCloseItem()` (`:237-245`) with:

Note the added `@MainActor`: the function now reads `state?.documentWindow`, and
`AppState` is `@MainActor`-isolated. Its only caller already wraps it in
`MainActor.assumeIsolated` (`ReaderMdApp.swift:233`), so no call site changes.

```swift
    @MainActor private func retargetCloseItem() {
        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        guard let close = items.first(where: {
            $0.action == #selector(NSWindow.performClose(_:))
                || $0.action == #selector(closeFileOrQuit(_:))
        }) else { return }

        // Restore, don't just skip: the retarget below is a persistent mutation,
        // so leaving it in place while Settings is key would close the document
        // from the menu — the bug the key-monitor guard fixes for ⌘W.
        guard let doc = state?.documentWindow, NSApp.keyWindow === doc else {
            close.target = nil
            close.action = #selector(NSWindow.performClose(_:))
            return
        }
        // Target is `self`, not nil: left to the responder chain the item validates as
        // disabled and the menu entry greys out.
        close.target = self
        close.action = #selector(closeFileOrQuit(_:))
    }
```

Note the widened `first(where:)` predicate — once the item has been retargeted once, its action is `closeFileOrQuit`, so the original lookup would no longer find it and the restore could never run.

- [ ] **Step 6: Build**

```bash
swift build
```

Expected: succeeds with no warnings about the new code.

- [ ] **Step 7: Verify no regression (no second window exists yet)**

```bash
swift run ReaderMd
```

Everything here must behave exactly as it did before this task — the guard is inert until Task 3 adds a second window, and this step proves it:

1. Open a markdown file, press ⌘W → the document closes, the window stays.
2. With no document open, press ⌘W → the "Quit Reader.md?" alert appears; Cancel it.
3. Open a file, pull down `File ▸ Close` → it is **enabled**, and clicking it closes the document.
4. With no document open, `File ▸ Close` → the quit alert.

If any of these regressed, `documentWindow` is not being set — add a temporary `print` inside the `WindowAccessor` closure to confirm it fires, before changing anything else.

- [ ] **Step 8: Commit**

```bash
git add Sources/ReaderMd/Views/WindowAccessor.swift Sources/ReaderMd/Models/AppState.swift Sources/ReaderMd/ContentView.swift Sources/ReaderMd/ReaderMdApp.swift
git commit -m "$(cat <<'EOF'
fix(window): scope the ⌘W document-close to the document window

The global key monitor swallowed ⌘W for any window, and retargetCloseItem
rewrote File ▸ Close permanently. Both were fine while the app had exactly
one window; a Settings window would have closed the user's document from
either path. Tag the document window and require it — and restore
performClose rather than bailing, or the stale menu retarget survives.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: The Settings window

**Files:**
- Create: `Sources/ReaderMd/Views/SettingsView.swift`
- Modify: `Sources/ReaderMd/Models/AppState.swift` (`setTheme`, `clearEditor`)
- Modify: `Sources/ReaderMd/ReaderMdApp.swift` (the scene)
- Test: `Tests/ReaderMdTests/EditableFileTests.swift`

**Interfaces:**
- Consumes: `AppState.exportLayout` / `setExportLayout(_:)` (Task 1); `AppState.documentWindow` and the guarded ⌘W monitor (Task 2).
- Produces:
  - `AppState.setTheme(_ value: AppearanceMode)`
  - `AppState.clearEditor()`
  - `struct SettingsView: View`

- [ ] **Step 1: Write the failing test for `clearEditor`**

Only `clearEditor` is new logic that `swift test` can reach; the rest of this task is SwiftUI binding, verified by hand in Step 8. Add to `Tests/ReaderMdTests/EditableFileTests.swift`, inside the existing class (it is already `@MainActor`):

```swift
    /// Settings ▸ Editing & Export can unset the editor outright. Before this
    /// there was no way back to "no editor" short of uninstalling the app —
    /// pickDefaultEditor only ever sets one.
    func testClearEditorForgetsTheStoredEditor() {
        let saved = Settings.loadEditorBundleID()
        defer { Settings.saveEditorBundleID(saved) }

        Settings.saveEditorBundleID("com.microsoft.VSCode")
        let state = AppState()
        state.clearEditor()

        XCTAssertNil(state.editorBundleID)
        XCTAssertNil(state.editorDisplayName)
        XCTAssertNil(Settings.loadEditorBundleID())
        XCTAssertEqual(state.openInEditorTitle, "Open in Editor")
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
swift test --filter EditableFileTests
```

Expected: FAIL — compile error, `value of type 'AppState' has no member 'clearEditor'`.

- [ ] **Step 3: Add `setTheme` and `clearEditor` to `AppState`**

In `Sources/ReaderMd/Models/AppState.swift`, add `setTheme` immediately after `toggleTheme()` ends at `:714`:

```swift
    /// Settings picks a mode outright; the toolbar button cycles. Both persist.
    func setTheme(_ value: AppearanceMode) {
        theme = value
        Settings.saveTheme(value)
    }
```

Add `clearEditor` immediately after `rememberEditor(_:)` ends at `:1055`:

```swift
    /// Forget the editor entirely — the inverse of `pickDefaultEditor`, offered
    /// in Settings. Same three lines `resolvedEditor()` runs when a stored
    /// bundle id stops resolving.
    func clearEditor() {
        editorBundleID = nil
        editorDisplayName = nil
        Settings.saveEditorBundleID(nil)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
swift test --filter EditableFileTests
```

Expected: PASS.

- [ ] **Step 5: Create `SettingsView`**

Create `Sources/ReaderMd/Views/SettingsView.swift`:

```swift
import SwiftUI

/// The ⌘, window. A second face on preferences that already round-trip through
/// AppState — every control here has a twin in the toolbar or a menu, except
/// the PDF layout default, which had no home before.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: Binding(
                    get: { state.theme },
                    set: { state.setTheme($0) }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Picker("Reading theme", selection: Binding(
                    get: { state.readingTheme },
                    set: { state.setReadingTheme($0) }
                )) {
                    ForEach(ReadingTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }

            Section("Reading") {
                // Continuous and already clamped to 0.7...1.6 by setFontScale;
                // a stepper would just be ⌘± with more clicks.
                LabeledContent("Text size") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { state.fontScale },
                                set: { state.setFontScale($0) }
                            ),
                            in: 0.7...1.6, step: 0.1
                        )
                        Text("\(Int((state.fontScale * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                Picker("Canvas width", selection: Binding(
                    get: { state.contentWidth },
                    set: { state.setContentWidth($0) }
                )) {
                    ForEach(ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
            }

            Section("Editing & Export") {
                LabeledContent("External editor") {
                    HStack {
                        Text(state.editorDisplayName ?? "None")
                            .foregroundStyle(state.editorDisplayName == nil ? .secondary : .primary)
                        Spacer()
                        if state.editorDisplayName != nil {
                            Button("Clear") { state.clearEditor() }
                        }
                        Button("Choose…") { state.pickDefaultEditor() }
                    }
                }

                Picker("PDF layout", selection: Binding(
                    get: { state.exportLayout },
                    set: { state.setExportLayout($0) }
                )) {
                    ForEach(ExportLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
```

- [ ] **Step 6: Add the scene**

In `Sources/ReaderMd/ReaderMdApp.swift`, add directly after the `WindowGroup`'s closing `.commands { … }` block — that is, after the `}` on `:175` and before the `}` closing `var body` on `:176`:

```swift

        // `SwiftUI.Settings`, qualified: Models/Settings.swift declares a
        // module-scope `enum Settings` that shadows the scene, and a module
        // declaration beats an imported one.
        //
        // The environment object and color scheme are not inherited from
        // ContentView — a Settings scene is a sibling, not a child.
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
        }
```

SwiftUI adds the `Settings… ⌘,` item to the app menu on its own; do not add a command for it.

- [ ] **Step 7: Build and run the full test suite**

```bash
swift build && swift test
```

Expected: build succeeds; all tests pass.

- [ ] **Step 8: Verify by hand**

```bash
swift run ReaderMd
```

Window management — the part Task 2 exists for:

1. ⌘, opens the Settings window.
2. With Settings focused, ⌘W closes **Settings**; the document stays open.
3. With Settings focused and no document open, ⌘W closes Settings and shows **no** quit alert.
4. With Settings closed, ⌘W still closes the document, and still shows the quit alert when no document is open.
5. With Settings focused, `File ▸ Close` is **enabled** (not greyed out) and closes Settings. If it greys out, target the settings window explicitly instead of `nil` in `retargetCloseItem` — a nil target validates as disabled, which is why the existing code used `self` (see the comment at `ReaderMdApp.swift:241`).
6. With Settings open, close the **document** window with its red button, then click the Dock icon. The document window must come back. If it does not, add to `AppDelegate`:

   ```swift
       func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
           // Settings counts as a visible window, so without this the document
           // window can be closed with no way back — there is no New Window
           // command (CommandGroup(replacing: .newItem) removed it).
           true
       }
   ```

   Do **not** add a "New Window" command; Reader.md is deliberately single-document.

Settings contents:

7. Change Appearance in Settings → the toolbar's sun/moon icon updates, and the Settings window itself re-tints.
8. Change Reading theme in Settings → the toolbar's `textformat.size` menu shows the new selection, and the content pane re-renders. Change it back from the toolbar → Settings follows.
9. Drag the Text size slider → the document text resizes live and the percentage label tracks it. Press ⌘0 → the slider snaps back to 100%.
10. Change Canvas width in Settings → the column resizes; ⇧⌘\ then advances from the new value.
11. `Choose…` opens the editor picker; picking one shows its name and reveals `Clear`. `Clear` returns the row to "None", greys out ⇧⌘E, and reverts the File menu item to "Open in Editor".
12. Set PDF layout to "Continuous" in Settings, press ⌘E → the save panel's popup reads "Continuous". Switch it to "Page by Page" in the panel and save → Settings still reads "Continuous".

- [ ] **Step 9: Commit**

```bash
git add Sources/ReaderMd/Views/SettingsView.swift Sources/ReaderMd/Models/AppState.swift Sources/ReaderMd/ReaderMdApp.swift Tests/ReaderMdTests/EditableFileTests.swift
git commit -m "$(cat <<'EOF'
feat(settings): add a ⌘, Settings window

Appearance, reading theme, text size, canvas width, external editor and
PDF layout in one grouped Form. Every control keeps its toolbar or menu
twin; the PDF layout default is the only one that had no home before.
Clearing the external editor is new — pickDefaultEditor could only set one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Documentation

The project mandates bundled docs first, then `docs/`, then the site — and the site edit is deferred to the release commit, so it is deliberately absent here.

**Files:**
- Modify: `Sources/ReaderMd/Resources/docs/SHORTCUTS.md`
- Modify: `Sources/ReaderMd/Resources/docs/CHANGELOG.md`
- Modify: `docs/features.md`

**Interfaces:**
- Consumes: the shipped behavior from Tasks 1–3.
- Produces: nothing code-facing.

- [ ] **Step 1: Fix the ⇧⌘E row and add ⌘, to `SHORTCUTS.md`**

In `Sources/ReaderMd/Resources/docs/SHORTCUTS.md`, the Files table currently has:

```
| ⇧⌘E | Open in Editor (pick one first via File → Set Default Editor…) |
```

Replace that row with:

```
| ⇧⌘E | Open in Editor (pick one first in Settings, or File → Set Default Editor…) |
```

Then add a new table at the end of the file, after the Help section:

```markdown
## Settings

| Shortcut | Action |
| --- | --- |
| ⌘, | Open Settings |

Appearance, reading theme, text size, canvas width, external editor, and the
default PDF export layout. Everything except the PDF layout is also reachable
from the toolbar or a menu — Settings is a second way in, not the only one.
```

- [ ] **Step 2: Add the changelog section**

`Sources/ReaderMd/Resources/docs/CHANGELOG.md` drives Sparkle's release notes, the GitHub release body, and the What's New sheet, so this text is user-facing three times over.

Read the file first to match its exact heading style and find the top of the entry list:

```bash
head -20 Sources/ReaderMd/Resources/docs/CHANGELOG.md
```

Add a new section above the current top entry, matching the heading format you just read (the version number is decided at release time — use the next unreleased version, `1.17.0`, since this adds a feature):

```markdown
## 1.17.0

- **Settings window (⌘,)** — appearance, reading theme, text size, canvas
  width, the external editor, and the default PDF export layout in one place.
  Every control still works from the toolbar and menus too.
- You can now clear the external editor from Settings; previously the only way
  to unset one was to uninstall it.
- The Layout popup in the ⌘E save panel is now a per-export choice. It used to
  overwrite your default, so exporting once as Continuous quietly changed every
  later export. The default now lives in Settings ▸ Editing & Export.
```

- [ ] **Step 3: Update `docs/features.md`**

Read it to find the shortcut table and the feature list:

```bash
grep -n "⇧⌘E\|^## \|Set Default Editor" docs/features.md
```

Make three edits:
1. Add a `| ⌘, | Open Settings |` row to the shortcut table, in the section that matches how the table is grouped there.
2. Apply the same ⇧⌘E wording fix as Step 1 if that string appears.
3. Add a short Settings paragraph to the feature list, matching the surrounding prose style:

```markdown
### Settings

⌘, opens a Settings window with appearance, reading theme, text size, canvas
width, the external editor, and the default PDF export layout. Everything
except the PDF layout default is also on the toolbar or in a menu.
```

- [ ] **Step 4: Verify the bundled docs render in the app**

```bash
swift run ReaderMd
```

Press ⌘/ (Help ▸ Keyboard Shortcuts) and confirm the new Settings table renders and the ⇧⌘E row reads correctly. Then Help ▸ Release Notes and confirm the 1.17.0 section renders. Both are bundled resources, so a stale build shows the old text — if you see the old text, quit and re-run.

- [ ] **Step 5: Confirm nothing under `web/` is staged**

```bash
git status --porcelain web/
```

Expected: no output. A push to `main` touching `web/` deploys the site immediately, which would advertise ⌘, before a build containing it exists. That edit belongs to the release commit.

- [ ] **Step 6: Commit**

```bash
git add Sources/ReaderMd/Resources/docs/SHORTCUTS.md Sources/ReaderMd/Resources/docs/CHANGELOG.md docs/features.md
git commit -m "$(cat <<'EOF'
docs: document the Settings window

Bundled shortcuts and changelog first, then docs/features.md. The ⇧⌘E row
pointed only at File → Set Default Editor…, which is no longer the only way
to pick one. web/src/data/content.ts is deliberately left for the release
commit — a push touching web/ deploys the site immediately.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Deferred to the release

Not part of this plan's commits. When cutting the release (follow the `release` skill):

- `web/src/data/content.ts` — mirror the `docs/features.md` changes.
- Confirm the `CHANGELOG.md` version heading matches the version being released; `release.sh` refuses to publish a version with no section.
- Bump `CFBundleShortVersionString` in `make-app.sh`, and the `showAboutPanel()` fallback string at `ReaderMdApp.swift:182`, which the project keeps in sync by hand.
