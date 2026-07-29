# Mermaid diagrams: zoom, pan, and fullscreen

**Date:** 2026-07-27
**Status:** Design approved, not implemented
**Issue:** [#38](https://github.com/jnahian/reader.md/issues/38)

## Summary

Large Mermaid diagrams render unreadably small and there is no way to inspect
them short of exporting the page. Add zoom, pan, and a fullscreen overlay to
rendered diagrams. Everything lands in the web layer — `template.html` (CSS) and
`bridge.js` (behavior) — plus a small simplification of `exportPDF()` on the
Swift side. No new dependency, no new theme variables.

## Why diagrams render small

Confirmed empirically against the bundled `mermaid.min.js` (11.16.0) with the
app's own `mermaid.initialize({ securityLevel: 'loose' })`, rendering
`graph TD` through Playwright:

```
<svg id="m1" width="100%" viewBox="0 0 198.6875 174" style="max-width: 198.6875px;" …>
```

Mermaid emits `width="100%"` plus a `max-width` cap at the diagram's natural
size. Inside the 760px content column a wide flowchart is scaled down to fit, so
its text shrinks with it. Because the SVG carries a `viewBox`, overriding that
cap scales the diagram back up **crisply** — it is vector, not raster. That is
the whole basis of the fullscreen behavior below.

Two further probe results constrain the design:

- **`<foreignObject>` is present.** Mermaid's flowchart labels are HTML by
  default (`htmlLabels: true`). SVG served through an `<img>` renders no
  `foreignObject` content, so the existing image lightbox (`bridge.js:293`,
  which works by `lightboxImg.src = img.src`) **cannot** be reused as-is —
  labels would come out as empty boxes. The overlay reuses the lightbox's CSS
  and open/close *pattern*, not its `<img>`.
- **Click directives are live.** The rendered SVG contains `<a>` and
  `g.node.default.clickable` elements, because `securityLevel: 'loose'` is set.
  Any click handler on the diagram body would swallow Mermaid `click`
  directives.

## Goals

- Read a large diagram at a usable size without leaving the document.
- Recover detail that fitting to the content column threw away.
- Never let a zoomed diagram bake into a ⌘E PDF export.

## Non-goals

Named so they read as deferred, not overlooked:

- Persisting zoom across reloads. FSEvents re-renders reset it, per the issue.
- Zoom controls on a Mermaid *parse error* block. That path replaces the
  container's contents with a `<pre class="error-msg">`; controls would be
  meaningless there.
- Vendoring `svg-pan-zoom`. It is transform math we write in a few lines.
- Native `WKPreferences.isElementFullscreenEnabled` / the Fullscreen API. A CSS
  overlay avoids the gating and leaves the window and toolbar untouched.

## Decisions

Each of these was a real fork; recording the choice and its cost.

| Decision | Chosen | Cost accepted |
| --- | --- | --- |
| Where zoom/pan lives | **Inline *and* in the overlay**, as the issue specs | Needs the export reset hook and the `ctrlKey`-gated wheel; an overlay-only design would have avoided both |
| How fullscreen opens | **Corner controls only** — no click handler on the diagram body | Diagrams open differently from images, which are click-to-lightbox |
| Inline wrapper height when zoomed | **Always fitted**; zoomed content is clipped and panned | A wide diagram fits *short*, so inline zoom is a slot; the overlay is the comfortable path for big diagrams |
| Which diagrams get controls | **All of them** | A two-box diagram carries four buttons it has no use for |
| Overlay's starting zoom | **Reset to fit**, restoring the inline zoom on close | Slightly more state than sharing one object; buys pan offsets that never need rescaling between viewports |

`click`-to-open and double-click-to-reset cannot coexist on one element — a
double-click fires two `click` events first, so it would open the overlay and
then reset. Corner-controls-only resolves that and the click-directive conflict
at the same time.

## Architecture

### DOM shape

`renderMermaid()` currently produces `div.mermaid > svg`. One div is inserted:

```
div.mermaid            position: relative; overflow: hidden   ← stays in flow
└─ div.mm-view         display: flex; justify-content: center
   ├─ svg              transform: translate(x,y) scale(s); transform-origin: 0 0
   └─ div.mm-controls  absolute, top-right; opacity 0 → 1 on .mermaid:hover
```

CSS transforms do not affect layout, so with fitted-height-always the wrapper
needs no explicit height and the prose below never moves while zooming.

`.mm-view` — not the wrapper — is what goes `position: fixed` for fullscreen.
Promoting the wrapper would pull it out of flow, shrinking `document.scrollHeight`;
that fires the scroll listener, which calls `reportProgress()`, which persists a
wrong reading position for the document. This is the same write-path trap found
at the end of the diff-mode work, where toggling diff mode destroyed the saved
reading position. Fullscreen *does* take `.mm-view` out of flow, so entering sets
`wrapper.style.height = wrapper.offsetHeight + 'px'` first and clears it on exit.

### Zoom and pan state

Per-diagram state is a plain object on the element: `view._zoom = {s: 1, x: 0, y: 0}`.
It dies with the node — no `WeakMap`, no registry to keep in sync with re-renders.
A single `apply(view)` writes the transform string.

- **Zoom toward cursor.** For a pointer at `(px, py)` in view coordinates and a
  scale change `s → s'`: `x' = px - (px - x) * (s'/s)`, likewise for `y`. Scale
  clamped to 0.25×–8×. The `+` / `−` buttons step by 1.25× and 1/1.25×, anchored
  at the view's centre since there is no pointer position; the wheel derives its
  factor from `deltaY` and anchors at the pointer.
- **Wheel.** Inline: `if (!e.ctrlKey) return` — a macOS trackpad pinch arrives as
  a `ctrlKey` wheel event, and plain wheel must keep scrolling the page. In
  fullscreen there is no page behind, so plain wheel zooms as well.
- **Pan.** `pointerdown` / `pointermove` / `pointerup` with `setPointerCapture`,
  guarded on `s > 1`: at or below fit nothing is hidden, so drag is inert and the
  cursor stays default. No drag library.
- **Double-click** resets to `{1, 0, 0}`.
- **No click handler on the diagram body**, so Mermaid `click` directives keep
  working.

### Controls

`−`, `+`, `↺`, `⤢`, styled after the existing `.copy-btn` (`template.html:100`):
11px, `1px solid var(--border)`, `background: var(--bg)`,
`color: var(--blockquote)`, `opacity: 0` with a 0.12s transition, revealed by
`.mermaid:hover .mm-controls`. Always visible while fullscreen. The `⤢` button
swaps its glyph to `✕` and its `title` to "Exit fullscreen" while open.

They reuse `--bg` / `--border` / `--fg` / `--blockquote`, which every theme
already defines, so no per-theme CSS is added. This matters: the file carries six
theme blocks, and the diff work had to add eight variables to each.

Controls live inside `.mm-view` so that they ride along when it becomes the fixed
overlay element and stay visible above the backdrop. The transform is on the
`svg`, not on `.mm-view`, so the controls are never scaled.

### Fullscreen

```css
.mm-view.fs { position: fixed; inset: 0; background: rgba(0,0,0,0.82); z-index: 999; }
```

Verified safe: nothing in the ancestor chain (`body`, `#content.markdown-body`)
sets `transform`, `filter`, `contain`, or `perspective`, so `fixed` resolves
against the viewport. (`.markdown-body` has `transition: max-width`, which is
not a containing-block trigger.)

Entering saves the inline `{s, x, y}`, resets to fit, and removes Mermaid's
inline `style="max-width: Npx"` so the vector fills the window. Exiting restores
both the cap and the saved inline zoom.

Exits: the `✕` control, **Esc** (one document-level `keydown` listener, registered
once, that tests for an open view — not one listener per diagram), and a click on
the backdrop, matching the image lightbox. The backdrop click is gated on the
pointer not having dragged, so releasing a pan over the backdrop does not close
the overlay.

### PDF export

Two new bridge entry points replace the current find-only sequence:

- `beforeExport()` — `clearFind()`, exit any open fullscreen, reset every diagram
  transform, remembering them.
- `afterExport()` — `refind()`, restore the transforms.

The Swift side gets **simpler**. `exportPDF()`
(`Sources/ReaderMd/Views/MarkdownWebView.swift:457`) currently branches on
`lastFindQuery.isEmpty` to skip the JS round trip. That branch collapses:
`clearFind()` on an unmarked document is a no-op, and `refind()` already guards
on `if (findQuery)` (`bridge.js:125`). So export becomes one unconditional
`beforeExport()` → `createPDF` → `afterExport()` chain, and the "PDF captures the
fitted diagram" requirement holds for both find highlights and diagram zoom
through a single hook rather than two.

### Find integration

`FIND_EXCLUDE` (`bridge.js:668`) is `'.anchor, .copy-btn, svg, .katex, .sr-only'`.
The control glyphs are text nodes in a `div`, so the existing `svg` entry does
not cover them; `.mm-controls` joins the list. Without it, ⌘F for `+` starts
matching diagram chrome.

### Re-render lifecycle

`setTheme` and FSEvents-driven reloads both re-render the diagrams, destroying
the nodes, their `_zoom` state, and any open overlay with them. That is
acceptable — zoom persistence is an explicit non-goal — and nothing leaks: state
lives on the discarded nodes, and the single Esc listener tests for an open view
before acting.

## Verification

Zoom-toward-cursor is the one piece that can be silently wrong: it looks
plausible until you notice the diagram creeping away from the pointer. Extract it
as a pure `zoomAt(state, factor, px, py)` and cover it with one `node --test`
file asserting the invariant that **the point under the cursor stays under the
cursor**, plus both clamp edges. `node --test` is stdlib — no framework, no
dependency, one file. It is not wired into `swift test`, which is a Swift-only
target.

Everything else is UI in a `WKWebView` and needs eyes on the running app, per the
repo's testing convention:

1. A wide flowchart: pinch-zoom inline, confirm the prose below does not move and
   the wrapper does not grow.
2. Plain two-finger scroll over a diagram still scrolls the page.
3. Pan at `s > 1`; confirm drag is inert at `s = 1`.
4. Fullscreen: opens fitted, Esc / `✕` / backdrop-click all exit, inline zoom
   restored on exit.
5. A diagram with a `click` directive: the node's link still fires.
6. ⌘E while a diagram is zoomed and find is active — PDF shows the fitted
   diagram and no highlights; both are restored afterward.
7. All six themes: control pill legible against the diagram and the backdrop.

## Pre-existing, out of scope

⌘E with the **image** lightbox open likely bakes the black backdrop into the
PDF — `#lightbox` is `position: fixed` and nothing clears it before `createPDF`.
`beforeExport()` is the natural place to fix it, but it is existing behavior and
not part of this change.
