# Share PDF — design

Add a **Share PDF…** action beside the existing PDF export, so a rendered
document can go straight to AirDrop, Mail, Messages, or any installed share
extension without first saving it somewhere.

The export toolbar button becomes a menu holding both actions.

## What is shared

The **rendered PDF**, not the source markdown — the point is that the receiver
does not need a markdown reader.

The layout is `state.exportLayout`, the Settings ▸ Editing & Export default. The
save panel's per-export layout override stays exclusive to the save panel: share
has no panel to hang an accessory picker on, and prompting for layout would put
a two-item submenu inside a two-item menu for a choice most people make once.

The system share menu is used whole rather than a bespoke AirDrop-only item.
`NSSharingServicePicker` supplies AirDrop, Mail, Messages, Notes, and every
installed extension for the same code, and macOS keeps that list current.

## Architecture

### Why not `ShareLink`

`ShareLink` is macOS 13+ and would drop straight into the menu, but it needs the
shared item to exist when the menu is *built*. The PDF does not exist until an
async render finishes. So this is `NSSharingServicePicker`, presented after the
render.

### Flow

Following the token-bump pattern:

1. `AppState` gains `shareToken: Int` and `@Published var sharing = false`.
   `triggerShare()` bumps the token.
2. `MarkdownWebView.updateNSView` reads the new token where it already reads
   `exportToken` (`MarkdownWebView.swift:177`) and calls `coord.sharePDF()`.
3. `sharePDF()` sets `state.sharing = true`, builds a temp URL, and runs the
   same render path export uses.
4. On success: `state.sharing = false`, then
   `NSSharingServicePicker(items: [url]).show(relativeTo:of:preferredEdge:)`.

Like `exportPDF()`, the entry point defers with `DispatchQueue.main.async` —
the token lands inside a SwiftUI render pass, and AppKit presentation started
from there does not attach reliably.

`state.sharing = true` goes **inside** that deferred block, not before it. The
token is read from `updateNSView`, so setting a `@Published` on the way in would
mutate observed state during a SwiftUI update pass — the "Publishing changes from
within view updates" warning, and a real source of update loops.

### The render must be shared, not reimplemented

`sharePDF()` goes through `beforeExport()` → render → `endExport()`, and
participates in the `activeExports` counter.

Both halves are load-bearing:

- Skipping `beforeExport()` / `afterExport()` bakes find highlights and diagram
  zoom into every shared PDF.
- Skipping `activeExports` lets a concurrent ⌘E export restore the highlights
  out from under an in-flight share render.

### The refactor this needs

`presentExportPanel()` currently welds destination-picking to rendering. Split
the render half out so both callers share it:

```swift
func renderPDF(to url: URL, layout: ExportLayout, completion: @escaping (Bool) -> Void)
```

It owns the `activeExports += 1`, the `beforeExport()` call, the
`.continuous` / `.pageByPage` switch, and `endExport()`.
`presentExportPanel()` keeps the panel and calls it with `completion` empty;
`sharePDF()` calls it directly with the temp URL and presents the picker from
the completion. `exportContinuous(to:)` and `exportPaginated(to:)` already take
a URL, so this is untangling, not restructuring.

Threading the completion down differs by path:

- **Continuous** — it goes in the `createPDF` result closure, after
  `data.write(to:)`, so it reports the write rather than the render.
- **Paginated** — the finish lands in `printOperationDidRun`, so the closure
  rides on `PendingExport` alongside `url` and `pageColor`. That is what
  `PendingExport` already exists for: one slot per in-flight export, so two
  concurrent ones do not share a completion.

**The completion must be delivered on the main queue.** `NSPrintOperation`
calls its `didRun` delegate on the thread that ran the operation, not the main
one, and `NSSharingServicePicker` traps on `dispatch_assert_queue` if shown from
anywhere else — a hard SIGTRAP, every time, on the page-by-page layout that is
the default. So `printOperationDidRun` hops to the main queue before calling the
completion, and `renderPDF`'s contract is "completion always on the main queue".
The continuous path needs nothing: `createPDF` already calls back on main.

**The completion must fire after `paintPageBackground`, not before.** That
function rewrites the finished PDF in place to fill the paper margins. Handing
the URL to the share picker while the rewrite is still running would AirDrop a
file being overwritten underneath the transfer. `printOperationDidRun` already
calls it synchronously, so the ordering is just "completion last" in that method
(the main-queue hop above is scheduled after it, so both constraints hold at once) — but it is the one place in this design where getting the order wrong
produces a corrupt file rather than a visible bug.

### Picker anchoring

`show(relativeTo:of:preferredEdge:)` needs a real `NSView`, and a SwiftUI
toolbar item does not hand you one. Park a zero-footprint `NSView` behind the
menu with `.background(ShareAnchor.Marker())` and anchor to that — it carries the
button's own frame, so the sheet hangs off the control that opened it. This is
the trick `DockTooltip` already uses to get a toolbar control's rect; the anchor
declines hit-testing, or it would eat the click that opens the menu.

Anchoring to the web view's top-trailing corner was tried first and is wrong:
with the outline pane open, that corner is the *outline's* edge, so the sheet
appeared over the outline instead of under the button. It survives only as the
fallback for a window whose toolbar is gone.

Digging the item out of `window.toolbar?.items` was rejected: it depends on
SwiftUI's generated item identifiers and would break silently.

### Temp file

`NSTemporaryDirectory()/Reader.md-Share/<uuid>/<docname>.pdf` — a per-share
subdirectory so the file keeps the document's real name, which is what AirDrop
shows the receiver and what lands in their Downloads.

`ShareTemp.url(for:)` creates the directory itself, with
`createDirectory(withIntermediateDirectories: true)`, before returning the URL —
`createPDF` and the print operation both write into a path that must already
exist, and neither reports a missing directory as anything louder than a file
that never appears.

Cleanup is one `removeItem` of `Reader.md-Share`, at launch and before any window
exists — `applicationDidFinishLaunching`, not a per-window or per-document path.
The file has to outlive the picker (an AirDrop transfer is still reading it after
the picker closes), so deleting on completion would need
`NSSharingServiceDelegate` plumbing to be correct; deleting last session's files
at launch is simpler and cannot race a transfer.

### Failure

If the render fails — `createPDF` errors, or the print operation cannot run
because the web view has no window — clear `sharing`, run `endExport()`, and
present nothing. This matches export, which already returns silently on a failed
render. An error alert here would be the only one in the app.

## UI surfaces

Share lands on all three surfaces export lives on today, and nowhere else.

### Toolbar

The export button (`Toolbar.swift:98`) becomes `exportMenu`, built like its two
neighbours `readingStyleMenu` and `canvasWidthMenu`:

```swift
Menu {
    Button("Export as PDF… (⌘E)") { state.triggerExport() }
    Button("Share PDF…")          { state.triggerShare() }
        .disabled(state.sharing)
} label: {
    if state.sharing {
        ProgressView().controlSize(.small)
    } else {
        Image(systemName: "square.and.arrow.up")
    }
}
.menuIndicator(.hidden)
.disabled(state.selectedFile == nil || state.canShowDiff)
.dockTooltip("Export and share")
```

The icon stays `square.and.arrow.up` — already the share glyph.

`sharing` disables the **share row**, not the menu. A disabled pull-down renders
its label greyed and static, so a `ProgressView` inside a disabled `Menu` is not
a dependable animating indicator — and an indicator that only shows while the
control is disabled is the entire point. Keeping the menu live also leaves ⌘E's
menu entry usable during a share, which costs nothing: concurrent exports are
already supported through `activeExports`.

Re-entrancy therefore does not rest on the disabled row alone. `triggerShare()`
carries `guard !sharing else { return }`, so the palette and the File menu — which
have no greyed row to look at — cannot start a second render either.

The spinner is not decoration. A long document with Mermaid and KaTeX takes a
visible moment to render, and without it a slow share reads as a dead click. If
the spinner turns out not to animate in a toolbar `Menu` label at all, fall back
to tinting the icon; do not fall back to nothing.

The menu is a plain menu, not `Menu(primaryAction:)`. A split button would keep
today's single-click export, but macOS split-button menus are hard to notice and
would hide the new action behind a click-and-hold. ⌘E remains the one-keystroke
path.

### File menu

`ReaderMdApp.swift:95` gains `Button("Share PDF…") { state.triggerShare() }`
immediately after "Export as PDF…", with the same disabled rule.

**No new keyboard shortcut.** Nothing obvious is free near ⌘E (⇧⌘E is the
external editor), and an action whose result is a picker is not keystroke-worthy.
This also keeps `ShortcutDocTests` out of the picture.

### Command palette

`QuickOpenView.swift:259` gains a `"share"` command beside `"export"`, inside
the same `if !state.canShowDiff` block — title "Share PDF…", subtitle
"Document", `systemImage: "square.and.arrow.up"`.

## Testing

The suite is pure logic; the render, the picker, and the anchoring are
WKWebView and AppKit and are verified by running the app.

### Unit

`ShareTempTests` — `ShareTemp.url(for:)` is pure:

- `/some/deep/README.md` → `…/Reader.md-Share/<uuid>/README.pdf`
- a path with no extension keeps its whole basename, plus `.pdf`
- a path with dots in the name (`notes.v2.md`) loses only the last component
- two calls return different directories
- a nil path falls back to `document.pdf`, as the save panel already does

`ShareGateTests` — `triggerShare()` bumps `shareToken`; `triggerShare()` while
`sharing` is set does **not** bump it; the toolbar's menu-level disabled
predicate is true when `selectedFile` is nil and when `canShowDiff` is set, and
unaffected by `sharing`.

### By hand, in the running app

- Share a long document: the spinner appears, the menu is disabled, the picker
  opens under the button.
- Start a share, then ⌘E while it renders: find highlights and diagram zoom are
  restored exactly once, after the last render finishes.
- AirDrop to a device: the received file is named `README.pdf`, not a UUID.
- Share with a find query active: the PDF has no highlights, and the original
  match is still selected afterwards.
- Share from a dark reading theme with the page-by-page layout: the received PDF
  has themed margins, i.e. the picker waited for `paintPageBackground`.

## Documentation

In the order `CLAUDE.md` prescribes.

1. `Sources/ReaderMd/Resources/docs/CHANGELOG.md` — the entry.
   `SHORTCUTS.md` is untouched (no new shortcut), so `ShortcutDocTests` stays
   green.
2. `docs/features.md` — one line under "Exporting and editing", beside the
   existing ⌘E line. The shortcut table at line 129 does not change.
3. `docs/features/exporting.md` — the prose: what is shared, that it uses the
   Settings layout default rather than asking, that the file is temporary.
4. `docs/features/exporting.shots.json` — the toolbar button is now a menu, so
   any existing shot of it is stale. Add a step that opens the menu and re-run
   `scripts/capture.sh` through the `reader-docs` skill rather than editing
   images.
5. `web/src/data/content.ts` — no change. The shortcut strip lists ⌘E, which
   still does what it says, and share is not a highlight card.

## Out of scope

- Sharing the source `.md` file.
- A share action on file-tree rows or in the sidebar context menu.
- Exporting or sharing while the diff view is up — share inherits export's
  existing `canShowDiff` block. That predicate is `diffMode && diffAvailable`
  (`AppState.swift:407`), so it means "the diff pane is currently displayed", not
  "this file has changes": a changed file in a repo is still exportable and
  shareable while it is being read normally.
