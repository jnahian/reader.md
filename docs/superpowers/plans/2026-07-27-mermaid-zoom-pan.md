# Mermaid Zoom, Pan, and Fullscreen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the reader zoom, pan, and fullscreen a rendered Mermaid diagram, so a large flowchart is readable without exporting the page.

**Architecture:** Purely additive in the web layer. `renderMermaid()` gains one inner wrapper (`div.mm-view`) that holds the SVG, carries per-diagram `{s, x, y}` zoom state on the DOM node, and becomes a `position: fixed` overlay for fullscreen. The zoom-toward-cursor math is extracted to `zoom.js` so `node --test` can cover it. On the Swift side, `exportPDF()` gets *smaller*: its find-only branch collapses into one unconditional `beforeExport()` / `afterExport()` pair that resets both find highlights and diagram zoom.

**Tech Stack:** Vanilla JS in a `WKWebView` (no modules — files load as plain `<script>`), CSS custom properties already defined by all six reading themes, `node --test` (stdlib) for the pure math, XCTest for the Swift side.

**Spec:** `docs/superpowers/specs/2026-07-27-mermaid-zoom-pan-design.md`
**Issue:** [#38](https://github.com/jnahian/reader.md/issues/38)

## Global Constraints

- **No new dependency.** Not `svg-pan-zoom`, not a drag library. Transform math only.
- **No new CSS custom properties.** Controls use `--bg`, `--border`, `--fg`, `--blockquote`, which all six theme blocks in `template.html` already define. Adding a variable means editing six blocks.
- **No click handler on the diagram body.** The app sets `securityLevel: 'loose'`, so Mermaid `click` directives are live; a body click handler would swallow them. Fullscreen opens from the corner control only.
- **Inline wrapper height is always the fitted height.** Zoomed content is clipped and panned. The prose below a diagram must never move while zooming.
- **Never let `.mermaid` itself become `position: fixed`.** It would leave the flow, shrink `document.scrollHeight`, fire the scroll listener, and persist a wrong reading position for the document. Only the inner `.mm-view` goes fixed.
- **Scale clamp is 0.25×–8×.** Button step is 1.25×, anchored at the view centre; wheel anchors at the pointer.
- **No zoom controls on a Mermaid parse-error block.** That path replaces the container with `<pre class="error-msg">`.
- `Package.swift` uses `.copy("Resources/web")` — a whole directory — so a new file under `Sources/ReaderMd/Resources/web/` needs no build-file change, and `make-app.sh` copies the bundle wholesale.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/ReaderMd/Resources/web/zoom.js` | **New.** Pure zoom math (`zoomAt`, `clampScale`) with no DOM access, so a node test can import it. Loaded as a global by `template.html`. |
| `Tests/web/zoom.test.js` | **New.** `node --test` coverage of the zoom invariant and the clamp edges. |
| `Sources/ReaderMd/Resources/web/template.html` | CSS for the wrapper, view, controls, and fullscreen overlay; one new `<script>` tag. |
| `Sources/ReaderMd/Resources/web/bridge.js` | `renderMermaid()` DOM shape; zoom state, controls, wheel/pan/dblclick handlers; fullscreen enter/exit; `beforeExport`/`afterExport`; one `FIND_EXCLUDE` entry. |
| `Sources/ReaderMd/Views/MarkdownWebView.swift` | `exportPDF()` / `generatePDF()` simplification. |

`bridge.js` is already ~800 lines and organised in labelled sections. The diagram code goes in one contiguous block after `renderMermaid()`, following that convention — do not restructure the file.

---

### Task 1: Pure zoom math + node test

The one piece that can be silently wrong: zoom-toward-cursor looks plausible until you notice the diagram creeping away from the pointer. It lives in its own file because `bridge.js` touches `document` at load time and cannot be imported by a test.

**Files:**
- Create: `Sources/ReaderMd/Resources/web/zoom.js`
- Create: `Tests/web/zoom.test.js`
- Modify: `Sources/ReaderMd/Resources/web/template.html:222` (add a `<script>` tag)

**Interfaces:**
- Consumes: nothing.
- Produces: browser globals `zoomAt(state, factor, px, py) -> {s, x, y}` and `clampScale(s) -> number`, plus constants `MIN_SCALE = 0.25` and `MAX_SCALE = 8`. `state` is `{s: number, x: number, y: number}`. `zoomAt` never mutates its argument. Tasks 2–4 call these as globals.

- [ ] **Step 1: Write the failing test**

Create `Tests/web/zoom.test.js`:

```js
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { zoomAt, clampScale, MIN_SCALE, MAX_SCALE } = require('../../Sources/ReaderMd/Resources/web/zoom.js');

// Where a diagram-space point `d` lands on screen along one axis.
const screenOf = (offset, scale, d) => offset + d * scale;

function assertPinned(before, factor, px, py) {
  // The diagram-space coordinates currently sitting under the pointer.
  const dx = (px - before.x) / before.s;
  const dy = (py - before.y) / before.s;
  const after = zoomAt(before, factor, px, py);
  const nx = screenOf(after.x, after.s, dx);
  const ny = screenOf(after.y, after.s, dy);
  assert.ok(Math.abs(nx - px) < 1e-9, `x drifted: ${nx} != ${px}`);
  assert.ok(Math.abs(ny - py) < 1e-9, `y drifted: ${ny} != ${py}`);
  return after;
}

test('zooming in from rest keeps the point under the cursor', () => {
  const after = assertPinned({ s: 1, x: 0, y: 0 }, 2, 300, 120);
  assert.equal(after.s, 2);
});

test('zooming from an already panned and zoomed state keeps the point pinned', () => {
  // The case a naive implementation gets wrong: it ignores the existing offset.
  assertPinned({ s: 2.5, x: -140, y: -30 }, 1.25, 410, 260);
});

test('zooming out keeps the point under the cursor', () => {
  assertPinned({ s: 4, x: -900, y: -220 }, 1 / 1.25, 55, 640);
});

test('at the top clamp the translation does not move either', () => {
  // Deriving the translation from the *requested* scale rather than the clamped
  // one makes the diagram drift every notch once you hit the limit.
  const before = { s: MAX_SCALE, x: -50, y: -60 };
  const after = zoomAt(before, 2, 300, 120);
  assert.equal(after.s, MAX_SCALE);
  assert.equal(after.x, -50);
  assert.equal(after.y, -60);
});

test('at the bottom clamp the translation does not move either', () => {
  const before = { s: MIN_SCALE, x: 12, y: 8 };
  const after = zoomAt(before, 0.5, 300, 120);
  assert.equal(after.s, MIN_SCALE);
  assert.equal(after.x, 12);
  assert.equal(after.y, 8);
});

test('zoomAt does not mutate its argument', () => {
  const before = { s: 1, x: 0, y: 0 };
  zoomAt(before, 2, 10, 10);
  assert.deepEqual(before, { s: 1, x: 0, y: 0 });
});

test('clampScale bounds both ends and passes the middle through', () => {
  assert.equal(clampScale(0.01), MIN_SCALE);
  assert.equal(clampScale(99), MAX_SCALE);
  assert.equal(clampScale(1.75), 1.75);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test "Tests/web/*.test.js"`
Expected: FAIL — `Cannot find module '../../Sources/ReaderMd/Resources/web/zoom.js'`

- [ ] **Step 3: Write the implementation**

Create `Sources/ReaderMd/Resources/web/zoom.js`:

```js
// Pure zoom math for rendered Mermaid diagrams (#38). Deliberately free of DOM
// access and kept out of bridge.js, which touches `document` at load time and so
// cannot be imported by a test.

const MIN_SCALE = 0.25;
const MAX_SCALE = 8;

function clampScale(s) {
  return Math.min(MAX_SCALE, Math.max(MIN_SCALE, s));
}

// Scale `state` by `factor`, keeping the point (px, py) — in the view's own
// coordinate space — pinned under the pointer. Returns a new state.
//
// The clamp is applied to the scale FIRST, so the translation is derived from the
// scale actually used. Deriving it from the requested scale makes the diagram
// drift a little on every notch once you are sitting at a limit.
function zoomAt(state, factor, px, py) {
  const s = clampScale(state.s * factor);
  const ratio = s / state.s;
  return {
    s,
    x: px - (px - state.x) * ratio,
    y: py - (py - state.y) * ratio,
  };
}

// The app loads this as a plain <script>, so the above stay globals. This tail is
// inert in the browser (`module` is undefined there) and is what the node test uses.
if (typeof module !== 'undefined') {
  module.exports = { zoomAt, clampScale, MIN_SCALE, MAX_SCALE };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `node --test "Tests/web/*.test.js"`
Expected: PASS — `# pass 7`, `# fail 0`

- [ ] **Step 5: Load the file in the web view**

In `Sources/ReaderMd/Resources/web/template.html`, add one line before the `bridge.js` tag (currently line 222) so `zoomAt` is a global by the time `bridge.js` runs:

```html
  <script src="mermaid.min.js"></script>
  <script src="zoom.js"></script>
  <script src="bridge.js"></script>
```

- [ ] **Step 6: Verify the app still builds and launches**

Run: `swift build && swift run ReaderMd`
Expected: builds warning-free, window opens, a markdown file with a mermaid block still renders its diagram (nothing has changed visually yet). Quit the app.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(mermaid): pure zoom-toward-cursor math

Its own file, not bridge.js: bridge.js touches document at load time, so a
node test can't import it. The clamp lands before the translation is derived —
otherwise the diagram drifts a notch at a time once you're at a limit." \
  --only -- Sources/ReaderMd/Resources/web/zoom.js Tests/web/zoom.test.js Sources/ReaderMd/Resources/web/template.html
```

---

### Task 2: DOM shape, CSS, and button zoom

Insert the `div.mm-view` wrapper, style it and the hover controls, and wire `−` / `+` / `↺`. No wheel or pan yet.

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/template.html:114` (replace the `.mermaid` rule)
- Modify: `Sources/ReaderMd/Resources/web/bridge.js:357-374` (`renderMermaid`), `bridge.js:668` (`FIND_EXCLUDE`)

**Interfaces:**
- Consumes: `zoomAt(state, factor, px, py)` and `clampScale(s)` globals from Task 1.
- Produces, for Tasks 3–5:
  - DOM: `div.mermaid > div.mm-view > (svg + div.mm-controls)`.
  - `zoomState(view) -> {s, x, y}` — lazily initialises and returns `view._zoom`.
  - `applyZoom(view) -> void` — writes the transform onto the view's `svg` and toggles `.pannable`.
  - `resetZoom(view) -> void` — sets `{s: 1, x: 0, y: 0}` and applies.
  - `zoomStep(view, factor) -> void` — centre-anchored zoom, used by the buttons.
  - `diagramControls(view) -> HTMLDivElement` — the `div.mm-controls` element.
  - `const STEP = 1.25`.

- [ ] **Step 1: Replace the `.mermaid` CSS rule**

In `Sources/ReaderMd/Resources/web/template.html`, replace line 114:

```css
    .mermaid { display: flex; justify-content: center; margin: 1em 0; }
```

with:

```css
    /* mermaid diagrams: zoom + pan (#38). The wrapper stays in flow and keeps its
       fitted height — transforms don't affect layout, so zooming never moves the
       prose below. overflow: hidden clips the zoomed svg; it does NOT clip the
       fullscreen overlay, because a position: fixed descendant escapes ancestor
       overflow unless that ancestor has a transform (none here). */
    .mermaid { display: flex; justify-content: center; margin: 1em 0; position: relative; overflow: hidden; }
    .mm-view { display: flex; justify-content: center; width: 100%; position: relative; }
    .mm-view.pannable { cursor: grab; }
    .mm-view.panning { cursor: grabbing; }
    .mm-controls {
      position: absolute; top: 8px; right: 8px; display: flex; gap: 4px;
      opacity: 0; transition: opacity 0.12s;
    }
    .mermaid:hover .mm-controls { opacity: 1; }
    .mm-controls button {
      width: 22px; height: 22px; padding: 0; font-size: 12px; line-height: 1;
      border: 1px solid var(--border); border-radius: 6px; background: var(--bg);
      color: var(--blockquote); cursor: pointer; font-family: -apple-system, sans-serif;
    }
    .mm-controls button:hover { color: var(--fg); }
```

- [ ] **Step 2: Add the zoom state and control helpers**

In `Sources/ReaderMd/Resources/web/bridge.js`, insert immediately after the `renderMermaid()` function (which ends at line 374):

```js
// ---- Mermaid diagram zoom (#38) ----

const STEP = 1.25;

// Zoom state lives on the element and dies with it: a re-render throws the node
// away, so there is no registry to invalidate.
function zoomState(view) {
  if (!view._zoom) view._zoom = { s: 1, x: 0, y: 0 };
  return view._zoom;
}

function applyZoom(view) {
  const svg = view.querySelector('svg');
  if (!svg) return;
  const { s, x, y } = zoomState(view);
  svg.style.transformOrigin = '0 0';
  svg.style.transform = `translate(${x}px, ${y}px) scale(${s})`;
  // At or below fit nothing is hidden, so there is nothing to drag towards.
  view.classList.toggle('pannable', s > 1);
}

function resetZoom(view) {
  view._zoom = { s: 1, x: 0, y: 0 };
  applyZoom(view);
}

// A button has no pointer position, so it anchors at the view's centre.
function zoomStep(view, factor) {
  const r = view.getBoundingClientRect();
  view._zoom = zoomAt(zoomState(view), factor, r.width / 2, r.height / 2);
  applyZoom(view);
}

function diagramControls(view) {
  const bar = document.createElement('div');
  bar.className = 'mm-controls';
  const button = (glyph, title, fn) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = glyph;
    b.title = title;
    b.addEventListener('click', fn);
    return b;
  };
  bar.append(
    button('−', 'Zoom out', () => zoomStep(view, 1 / STEP)),
    button('+', 'Zoom in', () => zoomStep(view, STEP)),
    button('↺', 'Reset zoom', () => resetZoom(view)),
  );
  return bar;
}
```

- [ ] **Step 3: Wrap the rendered SVG**

In `Sources/ReaderMd/Resources/web/bridge.js`, replace the body of `renderMermaid()` (lines 357–374) with:

```js
async function renderMermaid() {
  const blocks = contentEl.querySelectorAll('pre code.language-mermaid');
  for (const block of blocks) {
    const def = block.textContent;
    const container = document.createElement('div');
    container.className = 'mermaid';
    const id = `mermaid-${++mermaidCounter}`;
    try {
      const { svg } = await mermaid.render(id, def);
      const view = document.createElement('div');
      view.className = 'mm-view';
      view.innerHTML = svg;
      view.appendChild(diagramControls(view));
      container.appendChild(view);
    } catch (err) {
      // No controls on an error block: there is no diagram to zoom.
      container.innerHTML = `<pre class="error-msg">Mermaid error: ${escapeHtml(String(err.message || err))}</pre>`;
      const orphan = document.getElementById(`d${id}`);
      if (orphan) orphan.remove();
    }
    block.closest('pre').replaceWith(container);
  }
}
```

- [ ] **Step 4: Keep the control glyphs out of ⌘F**

In `Sources/ReaderMd/Resources/web/bridge.js`, line 668, add `.mm-controls` alongside the existing `.copy-btn` exclusion — the glyphs are text nodes in a `div`, so the `svg` entry does not cover them, and without this ⌘F for `+` starts matching diagram chrome:

```js
const FIND_EXCLUDE = '.anchor, .copy-btn, .mm-controls, svg, .katex, .sr-only';
```

- [ ] **Step 5: Verify the syntax parses**

Run: `node --check Sources/ReaderMd/Resources/web/bridge.js`
Expected: no output (exit 0).

- [ ] **Step 6: Verify in the running app**

Run: `swift run ReaderMd`, open a markdown file containing a wide mermaid diagram. Confirm, by eye:

1. Hovering the diagram fades in a three-button pill at its top right; moving away fades it out.
2. `+` enlarges the diagram, clipped at the wrapper's edges. **The prose below does not move.**
3. `−` shrinks it; `↺` returns it to exactly the original size and position.
4. Clicking `+` repeatedly stops at 8× rather than growing without bound, and the diagram does not creep sideways once it stops.
5. ⌘F for `+` reports no match from the diagram chrome.
6. A diagram with a deliberate syntax error (`graph TD\n  A --> `) still shows the red error text with **no** control pill.
7. Cycle the reading themes (⌘⌥1/2/3 or the toolbar) — the pill's border and glyphs stay legible in all six light/dark combinations.

Quit the app.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(mermaid): zoom controls on rendered diagrams

The svg gets an inner .mm-view wrapper. The transform goes on the svg, so the
wrapper keeps its fitted height and zooming never moves the prose below it." \
  --only -- Sources/ReaderMd/Resources/web/bridge.js Sources/ReaderMd/Resources/web/template.html
```

---

### Task 3: Wheel zoom, drag pan, double-click reset

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/bridge.js` (add `addDiagramZoom`, call it from `renderMermaid`)

**Interfaces:**
- Consumes: `zoomState`, `applyZoom`, `resetZoom`, `zoomAt` (Tasks 1–2).
- Produces: `addDiagramZoom(view) -> void`, and `view._dragged` (boolean) — set on pointer release to whether that gesture actually moved. Task 4 reads it so releasing a pan over the backdrop does not close the overlay.

- [ ] **Step 1: Add the gesture handlers**

In `Sources/ReaderMd/Resources/web/bridge.js`, insert after `diagramControls()` from Task 2:

```js
function addDiagramZoom(view) {
  view.addEventListener('wheel', (e) => {
    // A macOS trackpad pinch arrives as a ctrlKey wheel event. A plain wheel must
    // keep scrolling the page — except in fullscreen, where there is no page behind.
    if (!e.ctrlKey && !view.classList.contains('fs')) return;
    e.preventDefault();
    const r = view.getBoundingClientRect();
    view._zoom = zoomAt(zoomState(view), Math.exp(-e.deltaY / 200), e.clientX - r.left, e.clientY - r.top);
    applyZoom(view);
  }, { passive: false });

  view.addEventListener('dblclick', (e) => {
    // Double-clicking a button shouldn't also reset the whole diagram.
    if (e.target.closest('.mm-controls')) return;
    resetZoom(view);
  });

  let drag = null;
  view.addEventListener('pointerdown', (e) => {
    // Nothing is hidden at or below fit, so there is nothing to pan to.
    if (zoomState(view).s <= 1 || e.button !== 0) return;
    if (e.target.closest('.mm-controls')) return;
    drag = { x: e.clientX, y: e.clientY, moved: false };
    view.setPointerCapture(e.pointerId);
    view.classList.add('panning');
  });

  view.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const st = zoomState(view);
    view._zoom = { s: st.s, x: st.x + (e.clientX - drag.x), y: st.y + (e.clientY - drag.y) };
    drag.x = e.clientX;
    drag.y = e.clientY;
    drag.moved = true;
    applyZoom(view);
  });

  // Task 4's backdrop-click exit reads _dragged, so a pan that ends over the
  // backdrop doesn't also close the overlay.
  const endDrag = () => {
    view._dragged = !!(drag && drag.moved);
    drag = null;
    view.classList.remove('panning');
  };
  view.addEventListener('pointerup', endDrag);
  view.addEventListener('pointercancel', endDrag);
}
```

The `.fs` class in the wheel guard is added by Task 4. Until then the check is simply always false, which is the correct inline behavior.

- [ ] **Step 2: Call it for each rendered diagram**

In `renderMermaid()`, add one line after the `diagramControls` append:

```js
      view.appendChild(diagramControls(view));
      addDiagramZoom(view);
      container.appendChild(view);
```

- [ ] **Step 3: Verify the syntax parses**

Run: `node --check Sources/ReaderMd/Resources/web/bridge.js`
Expected: no output (exit 0).

- [ ] **Step 4: Verify in the running app**

Run: `swift run ReaderMd` and open a file with a wide mermaid diagram. Confirm:

1. **Trackpad pinch over the diagram zooms it**, and the point under the cursor stays under the cursor as it grows.
2. **Plain two-finger scroll over the diagram still scrolls the page** — this is the regression that matters most.
3. Zoomed past 1×, the cursor becomes a grab hand and dragging pans the diagram; the diagram does not jump when the drag starts.
4. At exactly 1× (after `↺`), the cursor is the default arrow and dragging does nothing.
5. Double-clicking the diagram resets it; double-clicking the `+` button does **not** reset it.
6. A mermaid diagram with a `click` directive — use `graph TD` / `A[Open]` / `click A "https://example.com"` — still opens the link in the browser when the node is clicked.

Quit the app.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(mermaid): pinch zoom and drag pan

Plain wheel is left alone so it still scrolls the page; a trackpad pinch
arrives as a ctrlKey wheel event, which is what we act on. Pan is gated on
scale > 1 — below fit there's nothing hidden to drag towards." \
  --only -- Sources/ReaderMd/Resources/web/bridge.js
```

---

### Task 4: Fullscreen overlay

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/template.html` (append fullscreen rules to the `#38` CSS block from Task 2)
- Modify: `Sources/ReaderMd/Resources/web/bridge.js` (`diagramControls`, plus enter/exit/Esc)

**Interfaces:**
- Consumes: `zoomState`, `applyZoom`, `resetZoom`, `diagramControls`, `view._dragged` (Tasks 2–3).
- Produces, for Task 5: `exitFullscreen(view) -> void`, and the `.mm-view.fs` selector as the way to find an open overlay (`document.querySelector('.mm-view.fs')`).

- [ ] **Step 1: Add the fullscreen CSS**

In `Sources/ReaderMd/Resources/web/template.html`, append to the `#38` block added in Task 2 (right after `.mm-controls button:hover`):

```css
    /* Fullscreen is a CSS overlay, not the Fullscreen API — no WKPreferences
       gating, and the window and toolbar are untouched. It is .mm-view that goes
       fixed, never .mermaid: taking the wrapper out of flow would shrink
       scrollHeight, and the scroll listener would persist a wrong reading position. */
    .mm-view.fs {
      position: fixed; inset: 0; z-index: 999; background: rgba(0,0,0,0.82);
      align-items: center; padding: 24px; box-sizing: border-box;
    }
    .mm-view.fs svg { max-height: 100%; }
    .mm-view.fs .mm-controls { opacity: 1; top: 16px; right: 16px; }
```

- [ ] **Step 2: Add enter, exit, and the Esc listener**

In `Sources/ReaderMd/Resources/web/bridge.js`, insert after `addDiagramZoom()`:

```js
function enterFullscreen(view) {
  const wrapper = view.parentElement;
  // .mm-view is about to leave the flow, so pin the wrapper's height first.
  // Letting the page reflow would shrink scrollHeight, and the scroll listener
  // would then persist a wrong reading position for the document.
  wrapper.style.height = `${wrapper.offsetHeight}px`;
  view._saved = zoomState(view);
  const svg = view.querySelector('svg');
  // Mermaid caps the svg at the diagram's natural width, which is exactly why a
  // big diagram looks small. Drop the cap so the vector fills the window; keep
  // the old value to restore on exit.
  view._maxWidth = svg ? svg.style.maxWidth : '';
  if (svg) svg.style.maxWidth = 'none';
  view.classList.add('fs');
  resetZoom(view);   // always opens fitted to the window
  setFullscreenButton(view, true);
}

function exitFullscreen(view) {
  const wrapper = view.parentElement;
  view.classList.remove('fs');
  wrapper.style.height = '';
  const svg = view.querySelector('svg');
  if (svg) svg.style.maxWidth = view._maxWidth || '';
  view._zoom = view._saved || { s: 1, x: 0, y: 0 };
  applyZoom(view);
  setFullscreenButton(view, false);
}

function setFullscreenButton(view, open) {
  const b = view.querySelector('.mm-fs');
  if (!b) return;
  b.textContent = open ? '✕' : '⤢';
  b.title = open ? 'Exit fullscreen' : 'Fullscreen';
}

// One listener for the whole document rather than one per diagram; inert unless
// something is actually open.
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const open = document.querySelector('.mm-view.fs');
  if (open) exitFullscreen(open);
});
```

- [ ] **Step 3: Add the fullscreen button and the backdrop exit**

In `diagramControls()`, replace the `bar.append(...)` call with:

```js
  const fs = button('⤢', 'Fullscreen', () => {
    view.classList.contains('fs') ? exitFullscreen(view) : enterFullscreen(view);
  });
  fs.className = 'mm-fs';
  bar.append(
    button('−', 'Zoom out', () => zoomStep(view, 1 / STEP)),
    button('+', 'Zoom in', () => zoomStep(view, STEP)),
    button('↺', 'Reset zoom', () => resetZoom(view)),
    fs,
  );
```

Then, in `addDiagramZoom()`, append one more handler — a click on the backdrop closes the overlay, matching the image lightbox, but only when the pointer did not drag:

```js
  view.addEventListener('click', (e) => {
    if (!view.classList.contains('fs')) return;
    // e.target === view means the backdrop itself, not the svg or the controls.
    if (e.target !== view || view._dragged) return;
    exitFullscreen(view);
  });
```

- [ ] **Step 4: Verify the syntax parses**

Run: `node --check Sources/ReaderMd/Resources/web/bridge.js`
Expected: no output (exit 0).

- [ ] **Step 5: Verify in the running app**

Run: `swift run ReaderMd` and open a file with a wide mermaid diagram. Confirm:

1. `⤢` fills the window with the diagram over a dark backdrop, **fitted and sharp** — text legible where it was not before. The glyph becomes `✕`.
2. A **tall** diagram in fullscreen is contained vertically rather than overflowing off-screen (this is what `max-height: 100%` is for — check it explicitly).
3. The overlay is **not clipped** by the wrapper's `overflow: hidden` — it genuinely covers the window.
4. Plain wheel/two-finger scroll now zooms (there is no page to scroll); pinch also zooms; drag pans.
5. All three exits work: `✕`, **Esc**, and a click on the dark backdrop. Ending a pan gesture with the pointer over the backdrop does **not** close it.
6. Zoom a diagram to ~3× inline, open fullscreen (it opens fitted, not at 3×), then exit — **the inline 3× is restored**.
7. Scroll to the middle of a long document, open and close fullscreen on a diagram: the scroll position does not move. Then quit, relaunch, and reopen the file — it resumes where you left it, not at the top.

Quit the app.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(mermaid): fullscreen diagram overlay

A CSS overlay on .mm-view, not the Fullscreen API. The wrapper's height is
pinned before the view leaves the flow — otherwise scrollHeight shrinks, the
scroll listener fires, and the document's saved reading position is destroyed.
Dropping mermaid's max-width cap is what lets the vector fill the window." \
  --only -- Sources/ReaderMd/Resources/web/bridge.js Sources/ReaderMd/Resources/web/template.html
```

---

### Task 5: Keep zoom out of the PDF

⌘E must capture the fitted diagram. This replaces the existing find-only clear/restore dance with one hook covering both, which makes the Swift side *smaller*.

**Files:**
- Modify: `Sources/ReaderMd/Resources/web/bridge.js:132-135` (add two methods to the `window.ReaderMd` object)
- Modify: `Sources/ReaderMd/Views/MarkdownWebView.swift:457-482` (`exportPDF`, `generatePDF`)

**Interfaces:**
- Consumes: `exitFullscreen(view)`, `resetZoom(view)`, `applyZoom(view)`, `.mm-view.fs` (Tasks 2–4); the existing `clearFind()` standalone function and the `refind()` method on `window.ReaderMd`.
- Produces: `window.ReaderMd.beforeExport()` and `window.ReaderMd.afterExport()`, both callable unconditionally — each no-ops when nothing is active.

- [ ] **Step 1: Add the two bridge methods**

In `Sources/ReaderMd/Resources/web/bridge.js`, inside the `window.ReaderMd` object, replace the trailing `clearFind()` entry (lines 132–134) with:

```js
  clearFind() {
    clearFind();
  },

  // ⌘E: find highlights and any diagram zoom would both bake into the PDF.
  // Reset them, snapshot, then put them back. One hook rather than two, because
  // Swift can't see which of the two is currently active — and both halves
  // no-op when nothing is, so the caller needs no state to branch on.
  beforeExport() {
    clearFind();
    const open = document.querySelector('.mm-view.fs');
    if (open) exitFullscreen(open);
    document.querySelectorAll('.mm-view').forEach((view) => {
      view._exportZoom = view._zoom;
      resetZoom(view);
    });
  },

  afterExport() {
    document.querySelectorAll('.mm-view').forEach((view) => {
      if (view._exportZoom) {
        view._zoom = view._exportZoom;
        applyZoom(view);
      }
      view._exportZoom = null;
    });
    // The method, not a bare function — refind() only exists on this object, and
    // it already guards on there being a live query.
    this.refind();
  },
```

- [ ] **Step 2: Simplify the Swift export path**

In `Sources/ReaderMd/Views/MarkdownWebView.swift`, replace `exportPDF()` and `generatePDF(restore:)` (lines 457–482) with:

```swift
        func exportPDF() {
            guard let webView else { return }
            // Find highlights and diagram zoom would both bake into the PDF.
            // beforeExport() resets them; wait for that JS to finish (completion
            // handler), snapshot, then afterExport() puts them back. Both halves
            // no-op when nothing is active, so there is no state to branch on here.
            webView.evaluateJavaScript("window.ReaderMd.beforeExport();") { [weak self] _, _ in
                self?.generatePDF()
            }
        }

        private func generatePDF() {
            guard let webView else { return }
            webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
                // afterExport() restores the exact find match the user was on;
                // find() would scroll them back to match 1 as a side effect of
                // exporting.
                self?.webView?.evaluateJavaScript("window.ReaderMd.afterExport();")
                guard case let .success(data) = result else { return }
                Task { @MainActor in self?.savePDF(data) }
            }
        }
```

`lastFindQuery` stays in use at `MarkdownWebView.swift:337`, `:445`, `:446`, and `:451`, so this leaves no orphan.

- [ ] **Step 3: Verify syntax and build**

Run: `node --check Sources/ReaderMd/Resources/web/bridge.js && swift build`
Expected: no JS output; Swift builds with no errors and no new warnings.

- [ ] **Step 4: Run the Swift suite**

Run: `swift test`
Expected: PASS, 172 tests, 0 failures (the pre-existing count — nothing here adds a Swift test).

- [ ] **Step 5: Run the node test**

Run: `node --test "Tests/web/*.test.js"`
Expected: PASS — `# pass 7`, `# fail 0`.

- [ ] **Step 6: Verify in the running app**

Run: `swift run ReaderMd` and open a file with a mermaid diagram. Confirm:

1. Zoom a diagram to ~4×, ⌘F for a word that appears several times, then ⌘E and save. The PDF shows the **fitted** diagram and **no** yellow highlights.
2. Back in the app after the export, the diagram is still at 4× and the find highlights are back, still focused on the same match (the counter does not reset to "1 of N").
3. ⌘E with nothing zoomed and no find active still produces a normal PDF.
4. ⌘E while a diagram is **fullscreen**: the overlay closes, and the PDF has no dark backdrop baked into it.

Quit the app.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(mermaid): reset zoom and fullscreen before PDF export

Collapses exportPDF's find-only branch: clearFind() on an unmarked document and
refind() with no query are both already no-ops, so one unconditional
beforeExport/afterExport pair covers highlights and diagram zoom together." \
  --only -- Sources/ReaderMd/Resources/web/bridge.js Sources/ReaderMd/Views/MarkdownWebView.swift
```

---

## Wrap-up

- [ ] **Add the changelog entry**

In `Sources/ReaderMd/Resources/docs/CHANGELOG.md`, under the existing `## [Unreleased]` → `### Added` list (which currently holds the diff-mode entries), append:

```markdown
- **Zoom into Mermaid diagrams.** Diagrams no longer have to fit the column
  width to be readable. Hover one for zoom controls, pinch to zoom, drag to pan,
  or open it fullscreen — it stays sharp at any size. ⌘E always exports the
  diagram at its fitted size.
```

- [ ] **Close the issue**

```bash
git commit -m "docs(changelog): mermaid diagram zoom" \
  --only -- Sources/ReaderMd/Resources/docs/CHANGELOG.md
gh issue close 38 --comment "Shipped: zoom, pan, and a fullscreen overlay on rendered diagrams."
```

Note for whoever runs this: the shared-working-tree lesson from the diff-mode run is why every commit above uses `git commit --only -- <paths>` rather than `git add` + `git commit` — the latter twice swept a concurrently-editing agent's staged changes into an unrelated commit.

## Known limitations, deliberately not addressed

- Zoom does not survive a re-render (`setTheme`, or an FSEvents-driven reload on file change). State lives on nodes that get thrown away. This is the issue's own non-goal.
- ⌘E with the **image** lightbox open likely bakes its black backdrop into the PDF. Pre-existing (`#lightbox` is `position: fixed` and nothing clears it), and `beforeExport()` is now the natural place to fix it — but out of scope here.
- The pure-math node test is not wired into `swift test`, which is a Swift-only target. It must be run as `node --test "Tests/web/*.test.js"`.
