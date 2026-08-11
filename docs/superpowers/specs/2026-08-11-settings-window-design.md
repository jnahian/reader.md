# Settings Window

A native ⌘, preferences window that gives Reader.md's scattered preferences a
single home.

## Problem

Reader.md has no `Settings` scene. `Models/Settings.swift` is persistence only —
a `UserDefaults` wrapper with no UI behind it. The preferences it stores are
spread across four places:

- the toolbar (appearance, reading theme, text size, canvas width),
- the File menu (Set Default Editor…, Install CLI Tool…),
- the View menu (text size and canvas width again),
- the ⌘E save panel, which is the *only* place PDF export layout can be changed.

Users look for a Settings window because every other Mac app has one. Export
layout in particular is invisible until you are already mid-export.

## Scope

**In the window** — six preferences, all already persisted today:

| Setting | `AppState` property | Existing setter |
| --- | --- | --- |
| Appearance (System/Light/Dark) | `theme` | `toggleTheme()` — needs a `setTheme(_:)` sibling |
| Reading theme | `readingTheme` | `setReadingTheme(_:)` |
| Text size | `fontScale` | `setFontScale(_:)` |
| Canvas width | `contentWidth` | `setContentWidth(_:)` |
| External editor | `editorBundleID` / `editorDisplayName` | `pickDefaultEditor()` |
| PDF export layout | *new* `exportLayout` | *new* `setExportLayout(_:)` |

**Not in the window.** Diff scope, resolved comment threads, sidebar width and
visibility, folders and remotes, recents and favorites. These are contextual
view state, not preferences — they belong where they are.

**Nothing is removed.** Every toolbar and menu control stays as a fast path,
including `File ▸ Set Default Editor…`. PDF export layout is the only setting
the window uniquely surfaces.

## Architecture

A `SwiftUI.Settings { }` scene in `ReaderMdApp.swift`, sibling to the
`WindowGroup`, wrapping a new `Views/SettingsView.swift`. SwiftUI adds the
"Settings… ⌘," item to the app menu automatically.

The scene needs its own `.environmentObject(state)` **and**
`.preferredColorScheme(state.colorScheme)` — neither is inherited from
`ContentView`. Binding appearance to `state.theme` then re-tints the Settings
window live, which is the correct feedback.

### The scene name collides with the persistence enum

`Models/Settings.swift` declares a module-scope `enum Settings`. Module
declarations win over imported ones, so a bare `Settings { … }` in the app body
resolves to the enum and fails to compile as a `Scene`.

Write `SwiftUI.Settings { … }` explicitly. Do not rename the persistence enum —
that touches ~40 call sites for no benefit.

### ⌘W must not reach the document from the Settings window

`AppDelegate.applicationDidFinishLaunching` (`ReaderMdApp.swift:215`) installs a
global `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` that swallows ⌘W
and calls `closeFileOrQuit`. Its only guards are `NSApp.modalWindow == nil` and
`keyWindow?.sheets.isEmpty`. A Settings window is neither modal nor sheeted, so
today's monitor would close the *document* — or pop the "Quit Reader.md?" alert
when no document is open — while the user is looking at Settings.

`retargetCloseItem()` (`ReaderMdApp.swift:237`) rewrites `File ▸ Close` to
`closeFileOrQuit` on every menu-tracking notification and has the same hole.

**Identifying the document window.** A small `WindowAccessor`
`NSViewRepresentable` on `ContentView` hands its `NSWindow` to `AppState` as a
plain `weak var documentWindow: NSWindow?` — deliberately not `@Published`,
since nothing renders from it and republishing on every window change would
churn the view tree.

`makeNSView` runs before the view is in a window, so `view.window` is nil there.
The assignment happens in `updateNSView` behind a `DispatchQueue.main.async` —
the same tick-later pattern the ⌘F focus grab (`Toolbar.swift:273`) and the
export panel (`MarkdownWebView.swift:477`) already use.

Chosen over sniffing the key window's identifier for
`com_apple_SwiftUI_Settings_window`: that string is undocumented and can change
between macOS releases, and the failure mode is the bug returning silently.

**The monitor** returns the event unhandled unless
`NSApp.keyWindow === state.documentWindow`, letting AppKit's `performClose`
close whatever window is focused. This fails *closed*: while `documentWindow` is
still nil (the first tick after launch), ⌘W closes the window rather than the
document. Brief, but it is a regression from today, which is why the assignment
must be deferred and not skipped.

**The retarget must restore, not bail.** `retargetCloseItem()` mutates a
persistent menu item — `close.target = self; close.action =
#selector(closeFileOrQuit(_:))` — and those assignments stick. An early `return`
when Settings is key would leave `File ▸ Close` still pointing at
`closeFileOrQuit` from the last time the document window was focused, so
clicking Close with Settings focused would close the *document*: the same bug,
reached through the menu instead of the key equivalent.

The non-document branch therefore actively restores the item:

```swift
close.target = nil
close.action = #selector(NSWindow.performClose(_:))
```

The comment at `ReaderMdApp.swift:241` notes that `target` was set to `self`
rather than nil precisely because a nil target validates as disabled — so
confirm by hand that the restored item is *enabled* when Settings is key. If it
greys out, target the settings window explicitly instead of nil.

## The window

```
┌─ Settings ──────────────────────────────┐
│  Appearance                             │
│    Appearance      ( System ▾ )         │
│    Reading theme   ( Standard ▾ )       │
│                                         │
│  Reading                                │
│    Text size       ●────────── 110%     │
│    Canvas width    ( Wide ▾ )           │
│                                         │
│  Editing & Export                       │
│    External editor  Cursor   [Choose…]  │
│    PDF layout      ( Page by Page ▾ )   │
└─────────────────────────────────────────┘
```

One `Form` with `.formStyle(.grouped)` and three `Section`s, given
`.frame(width: 420)` so the window has a fixed, deliberate width; height fits
the content. Single pane, no tabs — six settings across three sections fill one
pane, and a tab bar with two sparse tabs reads as unfinished. Tabs remain a
small change if the list ever grows past ~10 items.

Control choices:

- **Appearance, Reading theme, Canvas width, PDF layout** — `Picker`s over the
  enums' `allCases`, labelled by the existing `displayName`.
- **Text size** — a `Slider` over the existing 0.7–1.6 clamp, step 0.1, with a
  trailing percentage label ("110%"). Continuous and already clamped; a stepper
  would be ⌘± with more clicks.
- **External editor** — `editorDisplayName` (or "None") with a `Choose…` button
  calling the existing `pickDefaultEditor()`, plus a `Clear` button shown only
  when an editor is set. Clearing is new — today the only way to unset an editor
  is to uninstall it — and needs a `clearEditor()` on `AppState` that nils
  `editorBundleID` and `editorDisplayName` and calls
  `Settings.saveEditorBundleID(nil)`, the same three lines `resolvedEditor()`
  already runs when a bundle id stops resolving.

## Data flow

Unchanged from every other preference:

```
control → AppState.setX() → mutates @Published → Settings.saveX() → UserDefaults
```

The `@Published` change republishes to both the Settings window and the toolbar,
so the two faces cannot drift. Loading is unchanged — `AppState.init` already
reads every key.

### `exportLayout` moves into `AppState`

Today `MarkdownWebView`'s coordinator reads `Settings.loadExportLayout()` at
`MarkdownWebView.swift:492` and writes `Settings.saveExportLayout(layout)` at
`:503`, straight to `UserDefaults`, with no in-memory owner.

Add to `AppState`:

```swift
@Published private(set) var exportLayout: ExportLayout = .pageByPage
func setExportLayout(_ value: ExportLayout)   // mutate + Settings.saveExportLayout
```

seeded in `init` from `Settings.loadExportLayout()`.

The coordinator seeds the save panel's picker from `state.exportLayout` and uses
the picked value **for that export only**. It no longer writes the preference
back. All reads and writes route through `AppState`, never `Settings.*`
directly, or the `@Published` value goes stale after an export.

This is a deliberate behavior change: today a one-off "Continuous" export
silently becomes your default. After this change the save panel is a per-export
override and only Settings changes the default. It needs a changelog line.

## Failure modes

The three interesting ones already have handling to reuse:

- **Editor uninstalled** — `resolvedEditor()` (`AppState.swift:1017`) already
  clears the stale bundle id and nils `editorDisplayName`. The Settings row
  reads `editorDisplayName`, so it falls back to "None" on its own.
- **Unrecognized persisted value** — `ReadingTheme.named`, `ExportLayout.named`
  and `Settings.loadContentWidth` are already fail-closed to a default.
- **`pickDefaultEditor()` cancelled** — already a no-op.

Two failures are genuinely new, both rooted in the app having been built
single-window:

- **⌘W and `File ▸ Close`** reaching the document from the Settings window —
  the window guard and the menu-item restore above are the fix.
- **Closing the document window while Settings is open.**
  `applicationShouldTerminateAfterLastWindowClosed` returns `true`, and
  `CommandGroup(replacing: .newItem)` removed "New Window", so there is no menu
  path back to the `WindowGroup` window. With Settings open, clicking the
  document window's red close button no longer terminates the app — Settings is
  still a window — and may leave the user with Settings and no document window
  and no way back.

  **This must be verified by hand before it is fixed**: SwiftUI may restore the
  `WindowGroup` window on Dock-icon reopen, in which case there is nothing to
  do. If it does not, implement `applicationShouldHandleReopen(_:hasVisibleWindows:)`
  in `AppDelegate` to bring the document window back. Do not add a "New Window"
  command — Reader.md is deliberately single-document.

## Testing

`swift test` covers pure logic only, so most of this is verified by
`swift run ReaderMd`:

1. ⌘, opens the Settings window.
2. With Settings focused, ⌘W closes Settings and leaves the document open.
3. With Settings focused and no document open, ⌘W does not show the quit alert.
4. With Settings closed, ⌘W still closes the document, and still shows the quit
   alert when no document is open (no regression).
5. `File ▸ Close` behaves the same way in both cases — and is *enabled*, not
   greyed out, while Settings is focused.
6. With Settings open, close the document window with its red button, then click
   the Dock icon: the document window comes back.
7. Changing reading theme, appearance, text size or canvas width in Settings
   updates the toolbar menus, and vice versa.
8. Changing PDF layout in Settings changes the save panel's default; choosing
   the other option in the save panel does **not** change Settings.
9. Clearing the external editor greys out ⇧⌘E and reverts the menu title to
   "Open in Editor".

One unit test, fitting the existing editor-gate/marks pattern in
`ReaderMdTests`: the `exportLayout` round-trip through `AppState` — set,
persist, reload, and confirm a save-panel-style local choice does not mutate the
stored default.

## Documentation

In the project's mandated order (bundled docs → `docs/` → site data):

1. `Sources/ReaderMd/Resources/docs/SHORTCUTS.md` — add the ⌘, row. The ⇧⌘E row
   currently reads "pick one first via File → Set Default Editor…"; it becomes
   "…via Settings or File → Set Default Editor…".
2. `Sources/ReaderMd/Resources/docs/CHANGELOG.md` — the new Settings window, and
   the export-layout behavior change.
3. `docs/features.md` — shortcut table plus a Settings entry.
4. `web/src/data/content.ts` — mirror `docs/features.md`.

`FAQ.md` needs no change; nothing in it points at the old locations.

A push to `main` touching `web/` deploys Cloudflare Pages immediately, so the
`content.ts` edit goes in the **release** commit, not the feature commit —
otherwise the site advertises ⌘, before a build that has it exists.

## Files touched

| File | Change |
| --- | --- |
| `Sources/ReaderMd/Views/SettingsView.swift` | new — the `Form` |
| `Sources/ReaderMd/Views/WindowAccessor.swift` | new — tags the document window |
| `Sources/ReaderMd/ReaderMdApp.swift` | `SwiftUI.Settings` scene; key-window guard in the ⌘W monitor; restore-not-bail in `retargetCloseItem()`; `applicationShouldHandleReopen` if verification shows it is needed |
| `Sources/ReaderMd/Models/AppState.swift` | `documentWindow`, `exportLayout` + `setExportLayout`, `setTheme`, `clearEditor` |
| `Sources/ReaderMd/ContentView.swift` | attach `WindowAccessor` |
| `Sources/ReaderMd/Views/MarkdownWebView.swift` | save panel reads `state.exportLayout`, stops writing it back |
| `Tests/ReaderMdTests/` | `exportLayout` round-trip |
| docs (4 files above) | as listed |

## Out of scope

- Tabs, or any settings that do not exist today (startup behavior, update
  cadence, sidebar options).
- Renaming `enum Settings`.
- Removing any existing toolbar or menu control.
- Changing what `Settings.swift` persists or how.
