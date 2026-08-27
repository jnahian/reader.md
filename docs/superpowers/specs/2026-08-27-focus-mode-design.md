# Focus Mode — Design

**Date:** 2026-08-27
**Status:** Approved, ready for planning

A single toggle that strips the app down to the page: chrome hidden, window in
fullscreen, and every section but the one you're reading dimmed. Off by default,
never persisted across launches, and each of its four pieces switchable in
Settings.

## Why one toggle

Most of the chrome-hiding already exists as separate shortcuts — ⌘B collapses the
sidebar, ⇧⌘B the outline, ⇧⌘\ narrows the canvas, and macOS supplies fullscreen.
The value here is doing all of it at once *and putting it back*, plus the one
genuinely new thing: dimming everything outside the current section.

## What "current" means

The section under the active heading — everything from the current heading to the
**next heading at any level**. Not a viewport-centre band.

"Next heading of the same or higher level" was considered and rejected: it breaks
the very property this approach was chosen for. With `h2 A / p / h3 A.1 / p /
h2 B`, scrolling `A.1` from `top: 90px` to `top: 110px` flips the active heading
from `A.1` to `A`, and the lit region jumps from A.1's body to the whole of A — a
large block fading in and out over a 20px scroll. Bounding the region at the next
heading of any level means crossing a boundary always swaps two small adjacent
regions. It is also less code: an index range over the sibling list rather than
reading heading levels during the walk.

Centre-band dimming is an editor idea (iA Writer, Ulysses), where it works because
the cursor is where attention is. In a reader the eye runs ahead of the viewport
constantly, so a centre band dims exactly the text about to be read. Section
dimming instead matches a structure the app already shows in the outline, and —
because nothing changes while scrolling *within* a section — has no motion tied to
scroll velocity and nothing to feel twitchy. It also reuses the `activeHeading`
signal `bridge.js` already computes, so it costs a CSS class.

Dim to `opacity: .38` — still legible, so a glance back at the previous section
doesn't require leaving the mode — over a 200ms transition, so crossing a heading
is a fade rather than a flash.

## Entering and leaving

Three entry points, one method (`AppState.toggleFocusMode()`):

- `⌥⌘F` — free today, mnemonic, and one modifier from macOS's own ⌃⌘F fullscreen
  which focus mode invokes. (`⇧⌘↩` was rejected: it is already a Find Previous
  alias on the invisible buttons in `ContentView`.)
- **View ▸ Focus Mode** menu item.
- A `>` command in the ⌘P palette.

Under the default configuration, entering stashes the current layout, collapses
sidebar and outline, sets narrow canvas width, hides the toolbar, and calls
`toggleFullScreen`. Leaving unwinds all of it.

### The toolbar control

A button in the existing View group in `Toolbar.swift` —
`ToolbarItemGroup(placement: .primaryAction)`, the one already holding reading
style, canvas width, and the outline toggle. Focus goes last, so the cluster reads
reading style → width → outline → focus.

```swift
Button { state.toggleFocusMode() } label: {
    Image(systemName: "rectangle.inset.filled")
}
.dockTooltip("Focus mode (⌥⌘F)")
```

One icon, no on-state variant — matching the sidebar and outline toggles beside it,
which do not vary either. In the default configuration the button is hidden the
moment it is pressed, so an on-state would only ever show in the "Hide the toolbar
off" configuration: not worth a second symbol, or the availability question a
newer one would raise. The filled-centre variant
carries the on-state without a second control; AppKit draws the capsule.

Consequence, accepted rather than fixed: in the default configuration this button
hides itself the moment it is pressed, because focus mode hides the toolbar.
There is no reveal in any configuration, windowed or fullscreen, so the button
stays gone until ⌥⌘F or Esc brings the toolbar back. It is a permanent
round-trip control only when "Hide the toolbar" is switched off.

## The stash

`showSidebar`, `showTOC`, and `contentWidth` all persist to `UserDefaults` on write
(`Models/Settings.swift`). If focus mode set them through the normal setters
(`toggleSidebar()`, `setShowTOC()`, `setContentWidth()`), quitting while in focus
mode would leave the user's real preferences overwritten with focus mode's values —
they would return to a collapsed sidebar and narrow text with no focus mode on.

So focus mode does not use those setters. A single non-`@Published` `FocusStash?`
on `AppState` captures at entry:

- `showSidebar`
- `showTOC`
- `contentWidth`
- `wasAlreadyFullscreen`

Focus mode then mutates the `@Published` properties directly, skipping the save. On
exit the stash is replayed and discarded.

`wasAlreadyFullscreen` exists so that entering focus mode from a window that was
already in macOS fullscreen leaves it in fullscreen on exit, rather than dropping
it back to a window.

**Manual changes inside focus mode win.** Pressing ⌘B or ⇧⌘\ while in focus mode is
deliberate: it goes through the normal setters, persists, and *updates the stash*,
so exiting keeps the chosen value rather than snapping back.

## Esc

Esc never reaches AppKit while reading: `bridge.js` consumes it in two
`keydown` listeners — one for the Mermaid fullscreen overlay (`bridge.js:525`) and
one for the image lightbox (`bridge.js:661`).

So the exit path is a new final branch in the existing `bridge.js` Escape handler:
if no lightbox and no fullscreen diagram is open, and focus mode is on, post a new
`exitFocus` message.

`exitFocus` must be added to the literal array of accepted message names at
`MarkdownWebView.swift:93`. A `post()` whose name is absent from that array does
nothing and raises no error — a silent failure.

Swift's `WKScriptMessageHandler` then applies the precedence:

1. non-empty `findQuery` → clear it
2. `showQuickOpen` → dismiss it
3. `focusMode` → exit it
4. otherwise → nothing

Esc keeps every behaviour it has today; focus mode is only reached when there is
nothing else to dismiss.

## Toolbar hiding

The original plan delegated to AppKit: returning `.autoHideToolbar` +
`.autoHideMenuBar` from `window(_:willUseFullScreenPresentationOptions:)` was
expected to hide the toolbar in fullscreen and give a top-edge hover reveal for
free, with the two Settings switches ("Enter fullscreen" / "Hide the toolbar")
combining into four distinct behaviours depending on which were on. That
reveal was flagged as the one assumption in this design that had to be
confirmed against the running app before the implementation committed to it.

It didn't hold up. Tested live, the mechanism did nothing: the toolbar stayed
fully visible, and the pixels at the top of the screen were identical whether
the pointer sat there or at the window's centre. `presentationOptions` was
silently inert.

The fix was to stop delegating to AppKit and hide the toolbar directly with
the SwiftUI modifier `.toolbar(.hidden, for: .windowToolbar)`, applied the same
way regardless of the fullscreen setting — verified live, and it works. Two
things follow from dropping the AppKit path: there is no hover reveal in any
configuration, and the two switches no longer interact — toolbar hiding
behaves identically whether or not fullscreen is on. ⌥⌘F, ⎋, or the green
traffic-light button is the way back; ⌘F reveals the toolbar without leaving
focus mode.

### The floating close-document button

`ContentView.swift:83` draws a native ✕ over the content, gated on
`state.selectedFile != nil && !state.diagramFullscreen` — the `diagramFullscreen`
term exists because the button is drawn *above* the web view and the in-page
overlay cannot cover it. Focus mode has the same problem: it strips every other
piece of chrome and would leave this one button sitting on the page. The condition
gains `&& !state.focusMode`.

## Dimming in the web view

`reportActiveHeading()` in `bridge.js` already walks `h1,h2,h3,h4` and picks the
topmost heading above 100px, posting the id to Swift. It gains a second job: when
focus dimming is on, walk `contentEl`'s **top-level siblings** and add `.focus-dim`
to every block outside the active heading's region — the index range from the
active heading up to the next heading of any level.

No `<section>` wrappers. marked emits a flat `h2, p, p, h2, …` sibling list, and
mark anchoring (`TextAnchor`), find, footnotes, and diff hunks all read that flat
structure — wrapping would break anchor resolution silently.

One CSS rule:

```css
.focus-dim { opacity: .38; transition: opacity .2s ease; }
```

Swift's entire involvement is `window.ReaderMd.setFocusDim(bool)`, once per toggle.
Nothing new is published at scroll rate — not on `AppState`, and not on
`ReadingState` either, because the active heading is already known locally in JS at
the moment it is needed.

The scroll spy is debounced 60ms, comfortably inside the 200ms transition. No
change there.

### Re-apply points

The spy is wired only to `scroll`, so the classing pass must also run:

- inside `setFocusDim(true)` — otherwise toggling while stationary does nothing
  until the reader scrolls
- inside `loadMarkdown` and `reloadMarkdown` — a rebuilt DOM has lost the classes

### When dimming is suspended

- **while `findQuery` is non-empty** — a match inside a dimmed section is hard to
  spot
- **in diff mode** — the spy tracks `section.diff-hunk` rather than headings, and
  the layout is side-by-side
- **when the document has no headings** — one region means dimming has nothing to
  say

⌘F inside full takeover reveals the toolbar rather than exiting focus mode, so a
search does not cost the mode.

## Settings

A **Focus Mode** section in `SettingsView`, four switches, all defaulting on:

| Switch | Off means |
| --- | --- |
| Enter fullscreen | Focus mode stays in the current window |
| Dim other sections | Chrome-strip only; the page renders normally |
| Narrow the canvas | Canvas width is left as-is |
| Hide the toolbar | The toolbar stays, and the focus button stays clickable |

Four keys in `Models/Settings.swift`, loaded and saved alongside the existing
preferences. The switches persist; the mode itself never does — launching always
starts outside focus mode, so no one lands in a chromeless fullscreen window they
forgot they left on.

All four off is allowed and makes ⌥⌘F a no-op. Rather than forbid the combination
or force one piece on, the section shows a single line of explanatory text when
nothing is enabled.

## Documentation

`ShortcutDocTests` fails the build if a shortcut lands in the bundled
`SHORTCUTS.md` without a matching row in `docs/features.md`, so those two move
together — the new row goes in the **View** table beside ⇧⌘\.

1. `Sources/ReaderMd/Resources/docs/SHORTCUTS.md` — ⌥⌘F in the View table
2. `Sources/ReaderMd/Resources/docs/CHANGELOG.md` — the release entry
3. `docs/features.md` — the matching shortcut row plus a one-line feature entry
4. `docs/features/reading.md` — the prose, plus a shot added to
   `reading.shots.json` and captured through the `reader-docs` skill
5. `web/src/data/content.ts` — a slot on the compact shortcut strip

## Testing

`swift test` covers pure logic, and most of this is UI. Two things are both
testable and likely to break silently:

- **Stash capture and replay.** Enter with a known layout (sidebar on, outline off,
  wide), assert the `@Published` values changed and `UserDefaults` did not; exit,
  assert restoration. Plus the ⌘B-inside-focus-mode case updating the stash, and
  `wasAlreadyFullscreen` in both states.
- **Esc precedence.** A pure function over three booleans (find query non-empty,
  quick open showing, focus mode on) — a table test. The in-page overlay cases
  never reach Swift; `bridge.js` resolves them before posting `exitFocus`.

Dimming, toolbar hiding, and fullscreen are verified by running the app.

## Out of scope

- Reading timers, session goals, or do-not-disturb.
- A typewriter/centre-band dimming option — rejected above, not deferred.
- Per-document focus mode. The mode is a property of the window, not the file.
