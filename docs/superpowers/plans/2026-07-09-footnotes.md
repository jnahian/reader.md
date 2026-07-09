# Footnotes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render markdown footnotes (`[^1]` refs + `[^1]:` definitions) in Reader.md by vendoring the `marked-footnote` extension, wiring it into the web view, and styling the footnote section.

**Architecture:** No native/Swift changes. `marked` v12 gets a footnote extension via `marked.use(markedFootnote())`. The extension emits standard GFM footnote HTML (`<sup><a data-footnote-ref>`, `<section data-footnotes>` with `<hr>` + `<ol>`), and the existing `interceptLinks()` in `bridge.js` already scrolls any `#`-anchor, so ref/backref navigation works with zero new code. Only the footnote-section CSS (sizing) is code we write.

**Tech Stack:** Vendored `marked-footnote@1.4.0` (MIT, UMD build, zero deps, exposes `window.markedFootnote`), `marked` v12.0.2, bundled web assets, SwiftPM.

## Global Constraints

- **No JS test framework exists in this repo** (no jest/vitest/node test runner/jsdom). Do NOT write `npm test`, `jest`, `pytest`, or any JS test command — they do not exist. Verification is `swift build` (compiles), `swift run` (launches app), and opening a fixture markdown file to observe on-screen behavior.
- Deployment target is **macOS 13**; build toolchain requires **Xcode 26 / Swift 6.2+** with the macOS 26 SDK.
- The vendored file is `marked-footnote@1.4.0`, **MIT**, ~2,982 bytes (UMD build), zero deps, global `window.markedFootnote`, used as `marked.use(markedFootnote())`.
- **Package.swift needs NO edit.** `resources: [.copy("Resources/web")]` copies the whole `web/` directory, so the new `.js` is bundled automatically.
- **make-app.sh needs NO edit.** It copies the SwiftPM resource bundle wholesale (`cp -R "${b}"/* "${APP}/Contents/Resources/"`), so the new `.js` lands in the packaged `.app` automatically.
- **Commit messages:** Conventional Commits (`feat`/`fix`/`chore`/`docs`/`style`/`refactor`/`perf`/`test`). Use ONLY the message shown in each step. Do **NOT** append a `Co-Authored-By:` line. Do **NOT** append a "Generated with Claude Code" line. (This overrides any default git-commit trailer in the environment.)

---

## File Structure

- **Create:** `Sources/ReaderMd/Resources/web/marked-footnote.umd.js` — vendored extension, verbatim from npm + a license header comment.
- **Modify:** `Sources/ReaderMd/Resources/web/template.html` — add one `<script>` tag (load the extension) and one CSS block (footnote-section styling, item 3C).
- **Modify:** `Sources/ReaderMd/Resources/web/bridge.js` — add one line: `marked.use(markedFootnote())`.
- **No edit:** `Package.swift`, `make-app.sh` (see Global Constraints — both copy `web/` wholesale).
- **Throwaway fixtures (not committed):** `/private/tmp/rmd-fixtures/footnotes.md` and `/private/tmp/rmd-fixtures/no-footnotes.md` — the on-screen test artifacts. Created by the plan, opened in the running app, never added to git.

---

### Task 1: Render footnotes (vendor + wire)

Delivers original request items 2 (links to footnotes), 3A (separate section with a rule), and 3B (numbered order instead of `[^1]`). The three edits are atomic: the `<script>` tag alone is a no-op, and `marked.use(markedFootnote())` without the script throws a ReferenceError that blanks the whole page — so they land in one commit.

**Files:**
- Create: `Sources/ReaderMd/Resources/web/marked-footnote.umd.js`
- Modify: `Sources/ReaderMd/Resources/web/template.html:103` (script tags block)
- Modify: `Sources/ReaderMd/Resources/web/bridge.js:20` (beside `marked.setOptions`)

**Interfaces:**
- Consumes: global `marked` (from `marked.min.js`, already loaded).
- Produces: global `window.markedFootnote` (a factory; called as `markedFootnote()` to build the extension). Footnote HTML shape relied on by Task 2's CSS: `<section data-footnotes>` containing `<hr data-footnotes>` + `<ol><li id="footnote-N">…<a data-footnote-backref>↩</a></li></ol>`, and inline `<sup><a data-footnote-ref>N</a></sup>`.

- [x] **Step 1: Create the two fixture files**

Run:

```bash
mkdir -p /private/tmp/rmd-fixtures
cat > /private/tmp/rmd-fixtures/footnotes.md <<'EOF'
# Footnotes Fixture

Some introductory text so there is scroll distance before the notes.

The first claim needs a source[^1]. A second claim needs another one[^2].

## Filler

Paragraph one of filler to create vertical scroll distance between the
references above and the footnote section at the very bottom of the page.

Paragraph two of filler. Reader.md wraps content at a fixed width, so a few
repeated paragraphs are enough to push the footnote section off-screen.

Paragraph three of filler. Keep scrolling to reach the numbered notes and the
horizontal rule that precedes them.

Paragraph four of filler so the ref-to-note jump is a visibly large scroll.

Paragraph five of filler so the backref jump back up is also visibly large.

[^1]: The first note. Plain text only.

[^2]: The second note, which links to [example.com](https://example.com).
EOF
cat > /private/tmp/rmd-fixtures/no-footnotes.md <<'EOF'
# No Footnotes

This document has no footnote references at all. After this paragraph there
must be no trailing horizontal rule and no empty footnotes section.
EOF
echo "fixtures written:"; ls -l /private/tmp/rmd-fixtures/
```

Expected: both files listed.

- [ ] **Step 2: Establish the baseline failure (footnotes render literally)** _(SKIPPED — on-screen GUI observation; requires a human. Background agent cannot see the app window.)_

Run: `swift run`

In the app window: click **Add Folder** (in the *sidebar footer*, bottom-left — not the topbar, which has no folder button), choose `/private/tmp/rmd-fixtures`, then click `footnotes.md` in the sidebar.

Expected (the failure we are about to fix): the markers `[^1]` and `[^2]` appear as literal text in the body, and the line `[^1]: The first note. Plain text only.` renders as a literal paragraph. There is no numbered `1`/`2` superscript and no footnote section at the bottom.

Quit the app (⌘Q) before editing files.

- [x] **Step 3: Vendor `marked-footnote@1.4.0` with a license header**

Run:

```bash
cd /private/tmp
npm pack marked-footnote@1.4.0
tar -xzf marked-footnote-1.4.0.tgz
ls -l package/dist/index.umd.js
```

Expected: `marked-footnote-1.4.0.tgz` is created and extracts to `package/`; `package/dist/index.umd.js` exists (~2,982 bytes).

Then write the vendored file with a header comment prepended:

```bash
DEST="/Users/nahian/Projects/reader.md/Sources/ReaderMd/Resources/web/marked-footnote.umd.js"
{
  printf '%s\n' \
    '/*!' \
    ' * marked-footnote v1.4.0 (https://www.npmjs.com/package/marked-footnote)' \
    ' * MIT License. Vendored verbatim from the npm package dist/index.umd.js.' \
    ' */'
  cat /private/tmp/package/dist/index.umd.js
} > "$DEST"
```

- [x] **Step 4: Verify the vendored file defines the expected global**

Run:

```bash
grep -c 'markedFootnote' /Users/nahian/Projects/reader.md/Sources/ReaderMd/Resources/web/marked-footnote.umd.js
```

Expected: a count `>= 1` (the UMD build defines/exports `markedFootnote`). If it prints `0`, the wrong file was vendored — stop and re-fetch. (This catches a bad vendor before it looks like "footnotes just don't render.")

- [x] **Step 5: Load the extension in `template.html`**

In `Sources/ReaderMd/Resources/web/template.html`, the script block currently reads:

```html
  <script src="marked.min.js"></script>
  <script src="highlight.min.js"></script>
```

Change it to add the extension immediately after `marked.min.js` and before `bridge.js`:

```html
  <script src="marked.min.js"></script>
  <script src="marked-footnote.umd.js"></script>
  <script src="highlight.min.js"></script>
```

- [x] **Step 6: Register the extension in `bridge.js`**

In `Sources/ReaderMd/Resources/web/bridge.js`, this line exists:

```js
marked.setOptions({ gfm: true, breaks: false });
```

Add the footnote extension right after it:

```js
marked.setOptions({ gfm: true, breaks: false });
marked.use(markedFootnote());
```

- [x] **Step 7: Rebuild and verify footnotes render** _(`swift build` performed and passed. On-screen items 1–6 below SKIPPED — GUI observation, requires a human. Follow-up commit `fix:` enables `footnoteDivider: true` so the `<hr>` (item 2/item 5) is now emitted, and adds a `.sr-only` rule + bridge guards so the extension's `<h2>Footnotes</h2>` is hidden and kept out of the outline.)_

Run: `swift build`
Expected: builds with no errors.

Run: `swift run`

In the app: the `/private/tmp/rmd-fixtures` folder should still be a root; click `footnotes.md`. Confirm each of these observable checks (spec Verification items 1–5, 8):

1. **Item 1 — numbered, no raw markers:** the two references render as superscript `1` and `2`. The strings `[^1]`, `[^2]`, and `[^1]:` appear nowhere on screen.
2. **Item 5 — section at the bottom, preceded by a rule:** scroll to the end; there is a horizontal rule, then a numbered ordered list with the two note bodies.
3. **Item 3 — ref → note scroll:** scroll back up, click the superscript `1`. The page scrolls down to the first note. (Handled by existing `interceptLinks()` → `scrollToHeading()` for `#`-anchors.)
4. **Item 4 — backref → ref scroll:** click the `↩` at the end of note 1. The page scrolls back up to the reference.
5. **Item 2 — link inside a footnote:** in note 2, click the `example.com` link. It must open the **external browser** to `https://example.com` (the `openExternal` message fires), NOT scroll within the page.
6. **Item 8 — no empty section:** click `no-footnotes.md` in the sidebar. There is NO trailing horizontal rule and NO empty footnotes section after the paragraph.

(Optional consequence check, spec "Consequences": the word count in the topbar now includes footnote words — correct, not a defect.)

Quit the app (⌘Q).

- [x] **Step 8: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add Sources/ReaderMd/Resources/web/marked-footnote.umd.js Sources/ReaderMd/Resources/web/template.html Sources/ReaderMd/Resources/web/bridge.js
git commit -m "feat: render markdown footnotes via vendored marked-footnote"
```

---

### Task 2: Style the footnote section (item 3C)

Delivers original request item 3C (sizing). The footnote section currently renders at full body size; this CSS makes it ~0.875em, spaces the rule, and colors the backrefs. Because the sizes are `em` relative to `.markdown-body { font-size: var(--content-size) }`, they scale with the ⌘+/⌘− controls.

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/template.html` (add a CSS block inside `<style>`, immediately before `</style>`)

**Interfaces:**
- Consumes: the footnote HTML from Task 1 (`section[data-footnotes]`, its `hr`, `ol`, `li`; `sup a[data-footnote-ref]`; `a[data-footnote-backref]`), and the theme CSS variables `--blockquote`, `--accent`, `--border` (defined in `:root` / `html.dark` in the same file).
- Produces: nothing consumed by later tasks (final task).

- [ ] **Step 1: Establish the baseline (footnote section is full body size)** _(SKIPPED — on-screen GUI observation; requires a human.)_

Recreate the fixtures if they are gone (same content as Task 1, Step 1):

```bash
mkdir -p /private/tmp/rmd-fixtures
cat > /private/tmp/rmd-fixtures/footnotes.md <<'EOF'
# Footnotes Fixture

Some introductory text so there is scroll distance before the notes.

The first claim needs a source[^1]. A second claim needs another one[^2].

## Filler

Paragraph one of filler to create vertical scroll distance between the
references above and the footnote section at the very bottom of the page.

Paragraph two of filler. Reader.md wraps content at a fixed width, so a few
repeated paragraphs are enough to push the footnote section off-screen.

Paragraph three of filler. Keep scrolling to reach the numbered notes and the
horizontal rule that precedes them.

Paragraph four of filler so the ref-to-note jump is a visibly large scroll.

Paragraph five of filler so the backref jump back up is also visibly large.

[^1]: The first note. Plain text only.

[^2]: The second note, which links to [example.com](https://example.com).
EOF
```

Run: `swift run`, open `footnotes.md`, scroll to the footnote section.
Expected (baseline): the note text is the SAME size as the body text, the rule sits at the default `hr` spacing, and the `↩` backref is the accent link color. Quit the app (⌘Q).

- [x] **Step 2: Add the footnote CSS**

In `Sources/ReaderMd/Resources/web/template.html`, the `<style>` block ends with the image-lightbox rules:

```css
    #lightbox.open { display: flex; }
    #lightbox img { max-width: 92vw; max-height: 92vh; cursor: zoom-out; border-radius: 8px; }
  </style>
```

Insert the footnote block immediately before `</style>`:

```css
    #lightbox.open { display: flex; }
    #lightbox img { max-width: 92vw; max-height: 92vh; cursor: zoom-out; border-radius: 8px; }

    /* footnotes (item 3C) */
    section[data-footnotes] { font-size: 0.875em; }
    section[data-footnotes] hr { margin-top: 40px; }
    section[data-footnotes] ol { padding-left: 1.4em; }
    section[data-footnotes] li { margin: 0.4em 0; }
    sup a[data-footnote-ref] { text-decoration: none; padding: 0 2px; }
    a[data-footnote-backref] { text-decoration: none; color: var(--blockquote); margin-left: 4px; }
    a[data-footnote-backref]:hover { color: var(--accent); }
  </style>
```

- [x] **Step 3: Rebuild and verify the styling** _(`swift build` performed and passed. On-screen items 1–4 below SKIPPED — GUI observation, requires a human. The `hr` spacing item (2) is now live: follow-up `fix:` commit set `footnoteDivider: true`, so the `<hr>` is emitted and the `section[data-footnotes] hr` rule applies.)_

Additional REQUIRES-HUMAN checks (from the `fix:` follow-up commit):
- the word "Footnotes" is not visible anywhere on the page
- the sidebar outline shows no "Footnotes" entry, and that heading has no hover `#` anchor

Run: `swift build`
Expected: builds with no errors.

Run: `swift run`, open `footnotes.md`. Confirm these observable checks (spec Verification items 6, 7, and the styled form of 5):

1. **Sizing (item 3C):** the footnote note text is visibly smaller than the body text (~14px vs 16px).
2. **Rule spacing (item 5, styled):** there is clear extra space (40px) above the footnote rule.
3. **Item 6 — font scaling:** press ⌘+ a few times, then ⌘−. The footnote text scales up/down together with the body text (it stays proportionally smaller).
4. **Item 7 — light/dark:** toggle the theme. In light mode the `↩` backref is muted grey (`--blockquote`); in dark mode it is the lighter grey `--blockquote`; the rule tracks `--border` in both. Hovering a backref turns it the accent color.

Quit the app (⌘Q).

- [x] **Step 4: Commit**

```bash
cd /Users/nahian/Projects/reader.md
git add Sources/ReaderMd/Resources/web/template.html
git commit -m "style: size and color the footnote section"
```

---

## Self-Review

**1. Spec coverage** — every spec item maps to a task:

| Spec item | Task / Step |
| --- | --- |
| New file `marked-footnote.umd.js` (vendored + header) | Task 1, Steps 3–4 |
| `template.html` script tag after `marked.min.js`, before `bridge.js` | Task 1, Step 5 |
| `bridge.js` `marked.use(markedFootnote())` beside `setOptions` | Task 1, Step 6 |
| `template.html` footnote CSS (item 3C, all 7 rules) | Task 2, Step 2 |
| `make-app.sh` copies new `.js` (verify, no edit) | Global Constraints (mechanism stated) |
| `Package.swift` (verify, no edit) | Global Constraints (mechanism stated) |
| Verification item 1 (numbered, no raw markers) | Task 1, Step 7.1 |
| Verification item 2 (link in footnote → openExternal) | Task 1, Step 7.5 |
| Verification item 3 (ref → note scroll) | Task 1, Step 7.3 |
| Verification item 4 (backref → ref scroll) | Task 1, Step 7.4 |
| Verification item 5 (section below all, preceded by rule) | Task 1, Step 7.2; styled spacing Task 2, Step 3.2 |
| Verification item 6 (⌘+/⌘− scales footnote text) | Task 2, Step 3.3 |
| Verification item 7 (light/dark rule + backref color) | Task 2, Step 3.4 |
| Verification item 8 (no footnotes → no empty section/rule) | Task 1, Step 7.6 |

No gaps.

**2. Placeholder scan** — no `TBD`/`TODO`/`add appropriate…`/`similar to Task N`. All code (vendor commands, script tag, `marked.use` line, full CSS block, both fixtures) is present verbatim.

**3. Type/name consistency** — `markedFootnote` (global factory) is consistent across Task 1 Steps 4/6 and the Interfaces block. The HTML selectors produced in Task 1 (`section[data-footnotes]`, `hr`, `ol`, `li`, `sup a[data-footnote-ref]`, `a[data-footnote-backref]`) exactly match the selectors styled in Task 2. Fixture paths (`/private/tmp/rmd-fixtures/footnotes.md`, `no-footnotes.md`) are identical everywhere and recreated in Task 2 so a fresh subagent is not stranded. Commit messages carry no forbidden trailer.
