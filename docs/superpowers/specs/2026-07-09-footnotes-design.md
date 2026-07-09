# Footnotes — Design

**Status:** approved, not implemented
**Covers:** original request items 2 and 3 (A, B, C)

## Problem

Reader.md does not render markdown footnotes at all. `marked` v12 has no footnote
support and no extension is registered, so this input:

```markdown
Body text[^1].

[^1]: The note.
```

renders as two literal paragraphs — `Body text[^1].` and `[^1]: The note.` —
with the `[^1]` markers visible as plain text. Verified by running the bundled
`marked.min.js` directly.

This reframes the original request. Items 2 ("add links to the footnotes") and 3
("change the style of the footnotes") both presuppose that footnotes render. They
do not. Items 2 and 3 are therefore one feature — *implement footnotes* — not two
adjustments to existing output.

Note on item 3C ("currently it seems larger than the regular size"): confirmed
with the user that this observation came from another application, not Reader.md.
There is no oversized-footnote bug to fix; 3C is a target, not a regression.

## Approach

Vendor `marked-footnote@1.4.0` rather than hand-rolling a tokenizer.

- MIT licensed, 2,982 bytes (UMD build), zero dependencies
- peers on `marked >= 7.0.0`; the bundled `marked` is v12.0.2
- ships `dist/index.umd.js`, which exposes `window.markedFootnote`

Its output, confirmed by reading its source, is the standard GFM footnote shape.
**It must be configured** — two of its defaults are wrong for us:

```js
marked.use(markedFootnote({ footnoteDivider: true }));
```

`footnoteDivider` defaults to `false` (`footnoteDivider: f = !1` in the minified
source), so **the `<hr>` is not emitted unless we ask for it** — request item 3A
would silently never render. With it on:

```html
Body text<sup><a id="footnote-ref-1" href="#footnote-1" data-footnote-ref>1</a></sup>

<section class="footnotes" data-footnotes>
  <h2 id="footnote-label" class="sr-only">Footnotes</h2>
  <hr data-footnotes>
  <ol>
    <li id="footnote-1">The note. <a href="#footnote-ref-1" data-footnote-backref>↩</a></li>
  </ol>
</section>
```

The `<h2 class="sr-only">Footnotes</h2>` is not optional — the extension always
emits it as an accessibility label (`headingClass: o = "sr-only"`), and there is no
option to suppress it. `sr-only` is a Bootstrap/Tailwind convention that **does not
exist in this app's CSS**, so without a rule for it the word "Footnotes" renders
visibly. It also has two knock-on effects we must handle, because `bridge.js`
post-processes headings after `marked` runs:

- `postTOC()` scans `h1,h2,h3,h4` → "Footnotes" would appear in the sidebar outline.
- `assignHeadingIds()` scans the same set → it overwrites `id="footnote-label"`.
- `addHeadingAnchors()` would give it a hover `#` anchor.

That output satisfies three of the four sub-requests with no rendering code of our own:

| Request | Satisfied by |
| --- | --- |
| 2 — links to the footnotes | `data-footnote-ref` and `data-footnote-backref` anchors, in both directions |
| 3A — separate section with a horizontal line at the end of the doc | `<section data-footnotes>` containing `<hr data-footnotes>` — **only with `footnoteDivider: true`** |
| 3B — numbered order instead of `[^1]` | `<sup>1</sup>` |

The existing `interceptLinks()` in `bridge.js` already routes any `href`
beginning with `#` through `scrollToHeading()`, which is a plain
`getElementById` + `scrollIntoView`. Footnote refs and backrefs are exactly such
anchors, so **both scroll directions work with no new Swift and no new JS.**

Code we write: 3C's sizing, a `.sr-only` rule, and a heading-exclusion guard.

```css
.sr-only {
  position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px;
  overflow: hidden; clip: rect(0, 0, 0, 0); white-space: nowrap; border: 0;
}
```

`assignHeadingIds()`, `postTOC()`, and `addHeadingAnchors()` each gain the same
one-line guard — skip any heading inside the footnote section:

```js
if (h.closest('section[data-footnotes]')) return;
```

## Changes

**`Sources/ReaderMd/Resources/web/marked-footnote.umd.js`** (new)
Vendored verbatim from the npm package's `dist/index.umd.js`. Add a header
comment naming the package, version, and MIT license, matching how the other
vendored assets are treated.

**`Sources/ReaderMd/Resources/web/template.html`**
Add `<script src="marked-footnote.umd.js"></script>` after `marked.min.js` and
before `bridge.js`.

Add CSS. This is the whole of item 3C:

```css
section[data-footnotes] { font-size: 0.875em; }
section[data-footnotes] hr { margin-top: 40px; }
section[data-footnotes] ol { padding-left: 1.4em; }
section[data-footnotes] li { margin: 0.4em 0; }
sup a[data-footnote-ref] { text-decoration: none; padding: 0 2px; }
a[data-footnote-backref] { text-decoration: none; color: var(--blockquote); margin-left: 4px; }
a[data-footnote-backref]:hover { color: var(--accent); }
```

`0.875em` is GitHub's ratio — about 14px against the 16px default body size, and
because it is `em` relative to `.markdown-body`'s `font-size: var(--content-size)`,
it scales correctly with the ⌘+/⌘− font-scale controls.

**`Sources/ReaderMd/Resources/web/bridge.js`**
Beside the existing `marked.setOptions`:

```js
marked.use(markedFootnote({ footnoteDivider: true }));
```

Plus the guard in `assignHeadingIds()`, `postTOC()`, and `addHeadingAnchors()`, so
the extension's `sr-only` "Footnotes" heading stays out of the outline, keeps its
`footnote-label` id, and gets no hover anchor.

**`make-app.sh`** — confirm the new `.js` is copied into `Contents/Resources`.
The script copies the `web/` directory wholesale, so this is a verification step,
not an edit.

No Swift changes. No `AppState` changes. No new bridge messages.

## Consequences

Footnote text becomes part of `contentEl.textContent`. Two things follow, both
correct behavior rather than defects, but both worth checking:

- `postWordCount()` counts footnote words. Correct — they are words in the document.
- The marks feature can anchor a highlight inside a footnote. Correct, and it
  resolves stably because footnote output is deterministic per render.

Nested code (`code { font-size: 85% }`) inside a footnote compounds to ≈0.74× body
size. Acceptable; it is what GitHub does.

## Verification

A fixture document exercising:

1. Two footnotes, referenced in order → numbered `1` and `2`, no `[^…]` visible anywhere
2. A footnote whose body contains a markdown link → renders as a link, and clicking
   it posts `openExternal` rather than scrolling
3. Clicking a `<sup>` ref → scrolls to the note
4. Clicking the `↩` backref → scrolls back to the ref
5. The section renders below all other content, preceded by a rule
6. ⌘+ / ⌘− → footnote text scales with the body
7. Light and dark → the rule and backref use `--border` / `--blockquote`
8. A document with *no* footnotes → no empty `<section>`, no stray rule
9. The word "Footnotes" is **not visible** anywhere on the page (`.sr-only` works)
10. The sidebar outline shows no "Footnotes" entry, and the footnote section's
    heading has no hover `#` anchor
