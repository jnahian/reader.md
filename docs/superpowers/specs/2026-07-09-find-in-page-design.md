# Find in Page — count, highlight-all, next/prev — Design

**Status:** approved, not implemented
**Covers:** original request item 1

## Problem

Find-in-page exists (`FindBar.swift`, `AppState.findQuery`, the
`findNextToken` / `findPrevToken` pair, and `WKWebView.find` in
`MarkdownWebView.Coordinator`). What it lacks is everything the request asks for:

- **No match count.** `WKFindConfiguration` / `WKFindResult` expose only
  `matchFound: Bool`. The count is not obtainable from the native API.
- **No highlight-all.** Native find highlights the current match only.
- **No search icon.** Find is reachable by menu and keyboard only.
- **Wrong keybinding.** ⌘F is bound to *Filter Files* (the sidebar filter);
  find-in-page is on ⌘⇧F.

Because the count is unobtainable natively, any solution that keeps
`WKWebView.find` must compute the count in JS anyway — leaving two sources of
truth for "which match is current". So the native find goes.

## Approach

Implement find entirely in `bridge.js`, and drive it from Swift over the existing
`evaluateJavaScript` → `window.ReaderMd.*` channel.

Matching is **case-insensitive substring**. No regex, no whole-word, no
case toggle, no options UI.

### The text base is not `contentEl.textContent`

This is the crux of the design, and the one place a naive implementation breaks.

`bridge.js` already has `rangeFromOffsets()` and `resolveAnchor()`, which walk
*every* text node under `contentEl`. After `render()` completes, that text
includes four categories of text the reader never sees as prose:

| Source | Injected by | Text |
| --- | --- | --- |
| Heading anchors | `addHeadingAnchors()` | `#`, as the **first child of every h1–h4** |
| Code copy buttons | `addCodeCopyButtons()` | `Copy`, inside every `<pre>` |
| KaTeX | `renderMath()` | the LaTeX source, twice — rendered glyphs plus a hidden `<annotation encoding="application/x-tex">` MathML subtree |
| Mermaid | `renderMermaid()` | `<text>` nodes inside an inline `<svg>` (`container.innerHTML = svg`) |

Searching that text would match invisible annotation text and inflate the count.
Worse, wrapping a match inside the Mermaid subtree would insert an HTML `<mark>`
into an `<svg>`, which is not a valid SVG child and corrupts the diagram.

**Find therefore gets its own filtered text walker.** It does *not* reuse
`rangeFromOffsets` or `contentEl.textContent`.

```js
const FIND_EXCLUDE = '.anchor, .copy-btn, svg, .katex';

// [{ node, start, end }] over the visible prose, plus the concatenated string.
function findTextSegments() {
  const walker = document.createTreeWalker(contentEl, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) =>
      n.parentElement && !n.parentElement.closest(FIND_EXCLUDE)
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_REJECT,
  });
  // …accumulate node + cumulative offsets…
}
```

Excluding `.katex` wholesale makes rendered math unsearchable. Accepted: the
`katex-html` subtree splits glyphs across dozens of spans, so a substring match
across it would be unreliable even if attempted.

### The marks feature is NOT affected and must not be touched

It is tempting to conclude that `resolveAnchor` has the same bug and to "fix the
root cause" with one shared walker. **It does not, and we must not.**

A mark's `quote` / `prefix` / `suffix` is captured by `reportSelection()` on
mouseup — long after `addHeadingAnchors()` and `addCodeCopyButtons()` have run.
The same pollution is present when a mark is *written* and when it is *resolved*,
so the offsets are self-consistent and marks land correctly. Pollution only
misanchors when it differs between write and read, and it never does — every
injection is deterministic per render.

Find and marks have **different correct text bases**. Marks want the
polluted-but-consistent text. Find wants what the reader sees. Keep them separate.
Refactoring the marks anchoring here would risk re-anchoring every saved mark in
every document, for no gain.

### JS API

- `window.ReaderMd.find(query)` — clear previous find marks; if `query` is empty,
  post `{count: 0, index: 0}` and stop. Otherwise `indexOf` every
  case-insensitive occurrence over the filtered text, wrap each occurrence's
  node-segments in `<mark class="rmd-find">`, mark occurrence 0 `.current`,
  scroll it into view, post `{count, index}`.
- `window.ReaderMd.refind()` — re-apply the live query after the DOM was rebuilt
  (re-render, marks re-wrap, PDF export), **keeping the current match index and
  without scrolling**. This is not a convenience: `render()` preserves `scrollY`,
  so a re-application that scrolled to match 1 would fight it, and an FSEvents
  save while reading would yank the viewport away and reset "7 of 12" to "1 of 12".
  The index is clamped, since an edited file may hold fewer matches than before.
  `findFocus` is module-level and would otherwise survive a *document* switch, so
  `render()` resets it to 0 when `keepScroll` is false — `loadMarkdown` (a new file)
  restarts find at match 1; `reloadMarkdown` and `setTheme` (same file) hold position.
- `window.ReaderMd.findStep(forward)` — move `.current` by ±1 modulo `count`,
  `scrollIntoView({block: 'center'})`, post the new `{count, index}`.
- `window.ReaderMd.clearFind()` — unwrap `mark.rmd-find` and `normalize()`,
  mirroring the existing `clearHighlights()`.

Wrapping uses a small dedicated `wrapFindMatch(segments)` rather than the existing
`wrapRange()`. `wrapRange` walks the *unfiltered* node set intersecting a range,
so it could re-admit a `.copy-btn` or `svg` text node that the filter just
excluded. `wrapFindMatch` wraps exactly the segments the filtered walker produced.
It is ~15 lines and reuses `wrapRange`'s per-text-node technique: because each
wrap is confined to a single text node, `surroundContents()` can never partially
select an element and can never throw.

### Ordering

`clearFind()` → `applyMarks()` → `applyFind()`, always.

The rationale is **deterministic nesting**, not exception-safety. Both wrappers
are per-text-node and neither can throw. But if find marks are already in the DOM
when `applyMarks` re-wraps, the resulting nesting inverts
(`<mark rmd-find><mark rmd-highlight>` instead of the reverse) depending on
arrival order. Fixing the order keeps the CSS predictable.

## Changes

**`bridge.js`**
`findTextSegments`, `wrapFindMatch`, `clearFind`, the three `window.ReaderMd`
entries above, a `mark.rmd-find` CSS class, and a `findResult` post.

`render()` does **not** re-apply find itself. Re-application is driven from Swift
in the `"rendered"` handler (below), so that it happens after `applyMarks` and the
ordering rule holds. An FSEvents-triggered re-render therefore restores the
highlights and the count via the same single path as a normal load.

**`template.html`**

```css
mark.rmd-find          { background: rgba(250, 216, 60, 0.40); border-radius: 2px; color: inherit; }
mark.rmd-find.current  { background: rgba(255, 149, 0, 0.75); }
html.dark mark.rmd-find         { background: rgba(250, 216, 60, 0.28); }
html.dark mark.rmd-find.current { background: rgba(255, 149, 0, 0.60); }
```

**`AppState.swift`**
Add `@Published var findCount: Int = 0` and `@Published var findIndex: Int = 0`.
`findQuery`, `findNextToken`, `findPrevToken`, `showFind` are unchanged — the
token-bump pattern stays exactly as it is.

**`MarkdownWebView.swift`**
- Add `findResult` to the script-message handler name list and to
  `userContentController(_:didReceive:)`, writing `findCount` / `findIndex`.
- `applyFind` / `findStep` call `evaluateJavaScript` instead of `webView.find`.
  Delete `WKFindConfiguration` usage.
- Fold the find re-application into `applyMarks(json:)` — that way *every* driver
  that re-wraps marks (the `"rendered"` handler and the mark-change site in
  `updateNSView`) re-wraps find afterwards, and the ordering rule holds at both.
  It calls `refind()`, never `find()`.
- **Before `createPDF`, call `clearFind()`; re-apply after the completion
  handler fires.** Otherwise the exported PDF contains the search highlights.

**`FindBar.swift`**
A count label between the text field and the chevrons:

- `count > 0` → `"\(findIndex + 1) of \(findCount)"`, `.secondary`
- `count == 0 && !query.isEmpty` → `"No results"`, `.secondary`
- empty query → no label

Chevrons disable when `findCount == 0`. Closing the bar clears `findQuery`, which
already drives `applyFind("")` → `clearFind()`.

**`ReaderMdApp.swift`** — swap the bindings:

- `Find in Page` → ⌘F
- `Filter Files` → ⌘⇧F

This changes muscle memory for existing users and belongs in the release notes.

**`TopBar.swift`**
A `magnifyingglass` button in the right-hand glass capsule, before the reload
divider, setting `state.showFind = true`. Tooltip `"Find in page (⌘F)"`. Disabled
when `state.selectedFile == nil`, matching reload and export.

## Verification

1. Search a term appearing 5× → `"1 of 5"`, all five highlighted, first is `.current`
2. ⌘G / chevron-down → `"2 of 5"`, `.current` moves and scrolls into view
3. Wrap past the last match → back to `"1 of 5"`
4. A term with no match → `"No results"`, chevrons disabled
5. **A search term that overlaps an existing user highlight** → both render, nesting is stable, clicking still opens the mark popover
6. **A term appearing in a Mermaid node label** → the SVG is not corrupted and the count excludes it
7. **A term appearing in a LaTeX expression** → excluded from the count; no match inside the KaTeX subtree
8. Search `Copy` on a page with a code block → the copy button's label is not counted
9. Search `#` on a page with headings → heading anchors are not counted
10. Edit the file on disk while find is active → re-render re-applies highlights; the count stays correct
11. ⌘E while find is active → the PDF contains no find highlights
12. Case-insensitivity: `Foo` matches `foo` and `FOO`
13. With find active on match 5, click a *different* file in the sidebar → the new
    document's find restarts at match 1, not match 5
