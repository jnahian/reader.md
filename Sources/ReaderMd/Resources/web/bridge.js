/* global marked, hljs, renderMathInElement, mermaid */
// Bridge between the SwiftUI host and the markdown web view.

const contentEl = document.getElementById('content');
let mermaidCounter = 0;
let currentDir = '';
let diffMode = false;

// highlight.js stylesheet pairs [light, dark] per reading theme. Both hrefs are
// set on theme change (see setReadingTheme) so the currently-disabled sheet is
// already correct when the mode toggles — no flash of unstyled code.
const HLJS = {
  standard:  ['styles/github.min.css',             'styles/github-dark.min.css'],
  editorial: ['styles/atom-one-light.min.css',     'styles/atom-one-dark.min.css'],
  terminal:  ['styles/stackoverflow-light.min.css', 'styles/stackoverflow-dark.min.css'],
};

function isDark() { return document.documentElement.classList.contains('dark'); }

// macOS system accent (pushed from Swift as a resolved #rrggbb via setAccent).
// Applied only to the standard theme — editorial/terminal own their accents, so
// an inline --accent (which would win over their html[data-theme] rules) is
// removed while one of those is active. Re-evaluated on theme *and* accent change.
let systemAccent = null;
function applyAccent() {
  const root = document.documentElement;
  const isStandard = !root.dataset.theme;
  if (systemAccent && isStandard) root.style.setProperty('--accent', systemAccent);
  else root.style.removeProperty('--accent');
}

function post(name, body) {
  if (window.webkit && window.webkit.messageHandlers[name]) {
    window.webkit.messageHandlers[name].postMessage(body);
  }
}

function initMermaid() {
  mermaid.initialize({ startOnLoad: false, theme: isDark() ? 'dark' : 'default', securityLevel: 'loose' });
}

marked.setOptions({ gfm: true, breaks: false });
marked.use(markedFootnote({ footnoteDivider: true }));

// ---- Public API called from Swift via evaluateJavaScript ----

window.ReaderMd = {
  setTheme(dark) {
    document.documentElement.classList.toggle('dark', dark);
    document.getElementById('hljs-light').disabled = dark;
    document.getElementById('hljs-dark').disabled = !dark;
    initMermaid();
    // re-render mermaid diagrams for the new theme if a doc is loaded
    if (window.__lastMarkdown != null) {
      render(window.__lastMarkdown, currentDir, true);
    }
  },

  setReadingTheme(name) {
    const root = document.documentElement;
    // Standard must *remove* the attribute, not set it empty — html[data-theme=""]
    // would still match an attribute selector and shadow the :root defaults.
    if (name === 'standard') delete root.dataset.theme;
    else root.dataset.theme = name;
    const [light, dark] = HLJS[name] || HLJS.standard;
    document.getElementById('hljs-light').href = light;
    document.getElementById('hljs-dark').href = dark;
    applyAccent(); // standard ⇄ custom transition changes whether the accent applies
    initMermaid();
    if (window.__lastMarkdown != null) render(window.__lastMarkdown, currentDir, true);
  },

  setAccent(hex) {
    systemAccent = hex || null;
    applyAccent();
  },

  loadMarkdown(text, dir, resume) {
    render(text, dir, false, resume);
  },

  reloadMarkdown(text, dir) {
    render(text, dir, true);
  },

  // Diff mode replaces the rendered document wholesale. It deliberately does
  // NOT post toc/wordCount — Swift owns the outline here (one row per hunk),
  // and a word count of a diff means nothing.
  loadDiff(json) {
    diffMode = true;
    renderDiff(JSON.parse(json));
  },

  clearDiff() {
    diffMode = false;
  },

  scrollToHeading(id) {
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  },

  setFontScale(scale) {
    document.documentElement.style.setProperty('--content-size', `${16 * scale}px`);
  },

  setContentWidth(css) {
    document.documentElement.style.setProperty('--content-width', css);
  },

  setFocusDim(on, opacity, depth) {
    focusDim = on;
    focusDepth = depth;
    document.documentElement.style.setProperty('--focus-dim-opacity', opacity);
    applyFocusDim();
  },

  applyMarks(marksJSON) {
    applyMarks(marksJSON);
  },

  // A user-initiated search: focus the first match and scroll to it.
  find(query) {
    applyFindQuery(query, 0, true);
  },

  // A re-application after the DOM was rebuilt (re-render, marks re-wrap, PDF
  // export). Keeps the user's current match and does NOT scroll — otherwise
  // saving the file while reading would yank the viewport to match 1 and reset
  // the counter from "7 of 12" to "1 of 12".
  refind() {
    if (findQuery) applyFindQuery(findQuery, findFocus, false);
  },

  findStep(forward) {
    findStep(forward);
  },

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
    // Dimmed content would bake into the PDF at reduced opacity, making it
    // unreadable. Remove focus-dim so the export renders at full brightness.
    [...contentEl.children].forEach((b) => b.classList.remove('focus-dim'));
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
    applyFocusDim();
  },
};

// ---- Rendering ----

const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
const unquote = (s) => s.replace(/^(['"])([\s\S]*)\1$/, '$2');

// Split a leading YAML frontmatter block (--- ... ---) off the document and
// render it as a table (like VS Code's preview), so it isn't parsed as a
// setext heading. Returns { table, body }; table is '' when no frontmatter.
function splitFrontmatter(text) {
  const m = text.match(/^﻿?---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/);
  if (!m) return { table: '', body: text };

  const rows = [];
  const lines = m[1].split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const kv = lines[i].match(/^(\S[^:]*):[ \t]*(.*)$/);
    if (!kv) continue;
    const key = kv[1].trim();
    let inline = kv[2].trim();
    // Gather more-indented continuation lines (block scalars / lists).
    const cont = [];
    while (i + 1 < lines.length && /^[ \t]+\S/.test(lines[i + 1])) {
      cont.push(lines[++i].trim());
    }
    let valHtml;
    if (cont.length && cont.every((l) => l.startsWith('- '))) {
      valHtml = '<ul>' + cont.map((l) => `<li>${esc(unquote(l.slice(2).trim()))}</li>`).join('') + '</ul>';
    } else if (cont.length) {
      // Folded/literal block scalar: drop the >, |, >- etc. indicator.
      valHtml = esc(cont.join(inline === '|' || inline === '|-' ? '\n' : ' '));
    } else {
      valHtml = esc(unquote(inline));
    }
    rows.push(`<tr><td><strong>${esc(key)}</strong></td><td>${valHtml}</td></tr>`);
  }
  if (!rows.length) return { table: '', body: text };
  return { table: `<table class="frontmatter">${rows.join('')}</table>`, body: text.slice(m[0].length) };
}

async function render(text, dir, keepScroll, resume) {
  diffMode = false;
  const prevScroll = keepScroll ? window.scrollY : 0;
  window.__lastMarkdown = text;
  currentDir = dir || '';
  // A fresh document (loadMarkdown) restarts find at the first match; a re-render
  // of the same one (reloadMarkdown, setTheme) keeps the reader where they were.
  // Without this, opening a new file with find active would leave refind() focused
  // on the old match index, somewhere off-screen.
  if (!keepScroll) findFocus = 0;

  const { table, body } = splitFrontmatter(text);
  contentEl.innerHTML = table + marked.parse(body);

  assignHeadingIds();
  fixRelativeImages();
  highlightCode();
  renderMath();
  await renderMermaid();
  interceptLinks();
  postTOC();
  postWordCount();
  addCodeCopyButtons();
  addImageZoom();
  addHeadingAnchors();

  // A fresh document resumes at its saved fraction — measured here, after mermaid
  // and KaTeX have laid out, so scrollHeight is final. Images without intrinsic
  // dimensions can still land late and shift the target slightly.
  // ponytail: fraction, not an anchor. Good enough until reflow drift annoys someone.
  const max = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo(0, keepScroll ? prevScroll : (resume > 0 && max > 0 ? resume * max : 0));
  reportActiveHeading();
  reportProgress();
  applyFocusDim();
  post('rendered', true);
}

function renderDiff(payload) {
  window.scrollTo(0, 0);
  if (!payload.hunks || !payload.hunks.length) {
    contentEl.innerHTML = `<p class="diff-empty">${esc(payload.empty || 'No changes')}</p>`;
    return;
  }
  contentEl.innerHTML = payload.hunks.map(diffHunkHTML).join('');
  reportActiveHeading();
  reportProgress();
  post('rendered', true);
}

function diffHunkHTML(hunk) {
  const rows = hunk.rows.map(diffRowHTML).join('');
  const label = hunk.heading || 'Top of file';
  return `<section class="diff-hunk" id="${escapeHtml(hunk.id)}">
    <div class="diff-hunk-head">
      <span>${esc(label)}</span>
      <span class="add">+${hunk.additions}</span>
      <span class="del">−${hunk.deletions}</span>
    </div>
    <div class="diff-scroll"><table class="diff"><tbody>${rows}</tbody></table></div>
  </section>`;
}

function diffRowHTML(row) {
  return `<tr class="${row.kind}">${diffCellHTML(row.old, 'old')}${diffCellHTML(row.new, 'new')}</tr>`;
}

/// A null cell is a filler: the other side gained or lost a line here.
function diffCellHTML(cell, side) {
  if (!cell) return `<td class="diff-num"></td><td class="diff-text ${side}"></td>`;
  return `<td class="diff-num">${cell.n}</td>` +
         `<td class="diff-text ${side}">${spannedText(cell.text, cell.spans)}</td>`;
}

// Wraps the changed ranges in <span class="w">. Offsets count UNICODE SCALARS,
// which is exactly what the spread operator below iterates — [...text] yields
// code points, not UTF-16 units and not grapheme clusters. Swift emits scalar
// offsets for this reason (see WordSpan). Do not switch either side to
// Characters/graphemes alone: "👨‍👩‍👧" is 1 Swift Character but 5 elements here,
// and every span after such a cluster would land on the wrong text.
function spannedText(text, spans) {
  if (!spans || !spans.length) return esc(text);
  const chars = [...text];
  let out = '', cursor = 0;
  for (const [start, length] of spans) {
    out += esc(chars.slice(cursor, start).join(''));
    out += `<span class="w">${esc(chars.slice(start, start + length).join(''))}</span>`;
    cursor = start + length;
  }
  return out + esc(chars.slice(cursor).join(''));
}

function postWordCount() {
  const text = contentEl.textContent || '';
  const words = text.trim().split(/\s+/).filter(Boolean).length;
  post('wordCount', words);
}

function addCodeCopyButtons() {
  contentEl.querySelectorAll('pre').forEach((pre) => {
    if (pre.querySelector('.copy-btn')) return;
    const code = pre.querySelector('code');
    if (!code) return;
    const btn = document.createElement('button');
    btn.className = 'copy-btn';
    btn.textContent = 'Copy';
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(code.textContent);
        btn.textContent = 'Copied';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 1400);
      } catch { /* clipboard may be unavailable */ }
    });
    pre.appendChild(btn);
  });
}

function addImageZoom() {
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = lightbox.querySelector('img');
  contentEl.querySelectorAll('img').forEach((img) => {
    img.addEventListener('click', () => {
      lightboxImg.src = img.src;
      lightbox.classList.add('open');
    });
  });
  lightbox.onclick = () => lightbox.classList.remove('open');
}

function addHeadingAnchors() {
  contentEl.querySelectorAll('h1,h2,h3,h4').forEach((h) => {
    if (h.closest('section[data-footnotes]')) return;
    if (h.querySelector('.anchor')) return;
    const a = document.createElement('a');
    a.className = 'anchor';
    a.textContent = '#';
    a.href = `#${h.id}`;
    a.addEventListener('click', (e) => { e.preventDefault(); window.ReaderMd.scrollToHeading(h.id); });
    h.insertBefore(a, h.firstChild);
  });
}

function reportProgress() {
  const doc = document.documentElement;
  const max = doc.scrollHeight - window.innerHeight;
  const frac = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
  post('progress', frac);
}

function assignHeadingIds() {
  const seen = new Map();
  contentEl.querySelectorAll('h1,h2,h3,h4,h5,h6').forEach((h) => {
    if (h.closest('section[data-footnotes]')) return;
    let slug = (h.textContent.trim().toLowerCase().replace(/[^\w\s-]/g, '').replace(/\s+/g, '-')) || 'section';
    const n = seen.get(slug) || 0;
    seen.set(slug, n + 1);
    h.id = n ? `${slug}-${n}` : slug;
  });
}

function highlightCode() {
  contentEl.querySelectorAll('pre code').forEach((block) => {
    if ([...block.classList].includes('language-mermaid')) return;
    hljs.highlightElement(block);
  });
}

function renderMath() {
  if (typeof renderMathInElement !== 'function') return;
  renderMathInElement(contentEl, {
    delimiters: [
      { left: '$$', right: '$$', display: true },
      { left: '\\[', right: '\\]', display: true },
      { left: '$', right: '$', display: false },
      { left: '\\(', right: '\\)', display: false },
    ],
    ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code'],
    throwOnError: false,
  });
}

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
      addDiagramZoom(view);
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

// Convert a viewport point into the svg's own layout space, which is the space the
// zoom state's x/y live in. The two differ by the centring inset whenever the
// diagram is narrower than the column, because .mm-view centres it — anchoring in
// view space instead sends a small diagram flying off sideways by
// inset * (scale - 1). transform-origin is 0 0, so scaling never moves the origin
// and the layout position is just the rendered one minus the current translate.
function anchorIn(view, clientX, clientY) {
  const svg = view.querySelector('svg');
  const { x, y } = zoomState(view);
  const r = svg.getBoundingClientRect();
  return [clientX - (r.left - x), clientY - (r.top - y)];
}

// A button has no pointer position, so it anchors at the centre of what the reader
// can currently see — the view's centre.
function zoomStep(view, factor) {
  const r = view.getBoundingClientRect();
  view._zoom = zoomAt(zoomState(view), factor, ...anchorIn(view, r.left + r.width / 2, r.top + r.height / 2));
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
  return bar;
}

function enterFullscreen(view) {
  const wrapper = view.parentElement;
  // .mm-view is about to leave the flow, so pin the wrapper's height first.
  // Letting the page reflow would shrink scrollHeight, and the scroll listener
  // would then persist a wrong reading position for the document.
  // getBoundingClientRect, not offsetHeight: the latter rounds to an integer, and
  // pinning 31px over a real 30.8px shifts the page by the difference — small, but
  // the entire point of pinning is to not move the reader.
  wrapper.style.height = `${wrapper.getBoundingClientRect().height}px`;
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
  // The overlay is inside the web view, so native chrome drawn above it stays
  // visible — Swift hides the floating close-doc ✕ while this is open.
  post('diagramFullscreen', true);
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
  post('diagramFullscreen', false);
}

function setFullscreenButton(view, open) {
  const b = view.querySelector('.mm-fs');
  if (!b) return;
  b.textContent = open ? '✕' : '⤢';
  b.title = open ? 'Exit fullscreen' : 'Fullscreen';
}

// One listener for the whole document rather than one per diagram; inert unless
// something is actually open. Anything Escape does NOT consume in the page is
// handed to Swift, which owns the precedence (find, quick open, focus mode).
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  const open = document.querySelector('.mm-view.fs');
  if (open) { exitFullscreen(open); return; }
  // The lightbox has its own listener further down; it fires after this one, so
  // check the state directly rather than relying on ordering.
  const lightbox = document.getElementById('lightbox');
  if (lightbox && lightbox.classList.contains('open')) return;
  post('exitFocus', true);
});

function addDiagramZoom(view) {
  view.addEventListener('wheel', (e) => {
    // A macOS trackpad pinch arrives as a ctrlKey wheel event; ⌘-wheel is the same
    // gesture for a mouse. A plain wheel must keep scrolling the page — except in
    // fullscreen, where there is no page behind.
    if (!e.ctrlKey && !e.metaKey && !view.classList.contains('fs')) return;
    e.preventDefault();
    view._zoom = zoomAt(zoomState(view), Math.exp(-e.deltaY / 200), ...anchorIn(view, e.clientX, e.clientY));
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

  view.addEventListener('click', (e) => {
    if (!view.classList.contains('fs')) return;
    // e.target === view means the backdrop itself, not the svg or the controls.
    if (e.target !== view || view._dragged) return;
    exitFullscreen(view);
  });
}

function fixRelativeImages() {
  contentEl.querySelectorAll('img[src]').forEach((img) => {
    const src = img.getAttribute('src');
    if (!/^([a-z]+:|\/)/i.test(src)) {
      img.src = `file://${currentDir}/${src}`;
    }
  });
}

function interceptLinks() {
  contentEl.querySelectorAll('a[href]').forEach((a) => {
    const href = a.getAttribute('href');
    a.addEventListener('click', (e) => {
      e.preventDefault();
      if (/^https?:/i.test(href)) {
        post('openExternal', href);
      } else if (href.startsWith('#')) {
        window.ReaderMd.scrollToHeading(href.slice(1));
      } else if (/\.(md|markdown|mdown|mdx)(#.*)?$/i.test(href)) {
        const clean = href.split('#')[0];
        const target = clean.startsWith('/') ? clean : normalize(`${currentDir}/${clean}`);
        post('openFile', target);
      }
    });
  });
}

function normalize(p) {
  const parts = [];
  for (const part of p.split('/')) {
    if (part === '..') parts.pop();
    else if (part !== '.' && part !== '') parts.push(part);
  }
  return '/' + parts.join('/');
}

// ---- TOC + scrollspy ----

function postTOC() {
  const entries = [];
  contentEl.querySelectorAll('h1,h2,h3,h4').forEach((h) => {
    if (h.closest('section[data-footnotes]')) return;
    entries.push({ id: h.id, text: h.textContent, level: Number(h.tagName[1]) });
  });
  post('toc', entries);
}

let focusDim = false;
// The deepest heading level that ends a region; 4 = every heading, the default.
let focusDepth = 4;

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

  let active = headings[0];
  for (const i of headings) {
    if (blocks[i].getBoundingClientRect().top <= 100) active = i;
    else break;
  }
  const next = headings.find((i) => i > active) ?? blocks.length;
  blocks.forEach((b, i) => { if (i < active || i >= next) b.classList.add('focus-dim'); });
}

function reportActiveHeading() {
  // In diff mode the outline is hunks, not headings, so the spy scans hunk
  // containers instead. Same "topmost element above 100px" rule, same
  // activeHeading channel — AppState can't tell the difference.
  const els = diffMode
    ? [...contentEl.querySelectorAll('section.diff-hunk')]
    // Same exclusion as assignHeadingIds/postTOC/addHeadingAnchors: the footnote
    // extension's sr-only <h2> is a real h2. Without this, scrolling into the
    // footnotes posts activeHeading:"footnote-label", which matches no TOC row, so
    // the outline's active-row highlight silently vanishes.
    : [...contentEl.querySelectorAll('h1,h2,h3,h4')].filter((h) => !h.closest('section[data-footnotes]'));
  if (!els.length) return;
  let activeId = els[0].id;
  for (const el of els) {
    if (el.getBoundingClientRect().top <= 100) activeId = el.id;
    else break;
  }
  post('activeHeading', activeId);
  applyFocusDim();
}

let spyTimer = null;
window.addEventListener('scroll', () => {
  reportProgress();
  clearTimeout(spyTimer);
  spyTimer = setTimeout(reportActiveHeading, 60);
}, { passive: true });

// Keep the lightbox reachable with Escape.
window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') document.getElementById('lightbox').classList.remove('open');
});

function escapeHtml(s) {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// ---- Highlighting (#1) ----
//
// Marks are anchored with a TextQuoteSelector (quote + prefix/suffix context,
// plus a startOffset tiebreaker) resolved against contentEl's plain-text
// render, not DOM offsets — the HTML is regenerated by marked on every
// render. Swift owns persistence; this module only resolves anchors onto the
// current DOM and reports selections/clicks back to Swift.

function clearHighlights() {
  contentEl.querySelectorAll('mark.rmd-highlight').forEach((mark) => {
    const parent = mark.parentNode;
    if (!parent) return;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  });
}

// Plain-text char offset (within contentEl.textContent) for a DOM Range's
// boundaries, walking contentEl's text nodes in document order.
function offsetsFromRange(range) {
  const walker = document.createTreeWalker(contentEl, NodeFilter.SHOW_TEXT);
  let node;
  let pos = 0;
  let start = null;
  let end = null;
  while ((node = walker.nextNode())) {
    const len = node.textContent.length;
    if (node === range.startContainer) start = pos + range.startOffset;
    if (node === range.endContainer) { end = pos + range.endOffset; break; }
    pos += len;
  }
  if (start === null || end === null) return null;
  return { start, end };
}

// Inverse of offsetsFromRange: build a DOM Range spanning the given plain-text
// char offsets.
function rangeFromOffsets(start, end) {
  const walker = document.createTreeWalker(contentEl, NodeFilter.SHOW_TEXT);
  let node;
  let pos = 0;
  let startNode;
  let startOffset = 0;
  let endNode;
  let endOffset = 0;
  while ((node = walker.nextNode())) {
    const len = node.textContent.length;
    if (!startNode && pos + len >= start) { startNode = node; startOffset = start - pos; }
    if (pos + len >= end) { endNode = node; endOffset = end - pos; break; }
    pos += len;
  }
  if (!startNode || !endNode) return null;
  const range = document.createRange();
  range.setStart(startNode, startOffset);
  range.setEnd(endNode, endOffset);
  return range;
}

// Resolve a TextQuoteSelector to plain-text offsets. Picks the occurrence
// whose surrounding prefix/suffix match, falling back to the one nearest
// startOffset when the quote repeats. Returns null only when the quote text
// is gone entirely (an orphaned mark).
function resolveAnchor(anchor) {
  const { quote, prefix, suffix, startOffset } = anchor;
  if (!quote) return null;
  const text = contentEl.textContent;
  const candidates = [];
  let idx = text.indexOf(quote);
  while (idx !== -1) {
    candidates.push(idx);
    idx = text.indexOf(quote, idx + 1);
  }
  if (!candidates.length) return null;

  const matching = candidates.filter((i) => {
    const pre = text.slice(Math.max(0, i - prefix.length), i);
    const suf = text.slice(i + quote.length, i + quote.length + suffix.length);
    return pre === prefix && suf === suffix;
  });
  const pool = matching.length ? matching : candidates;
  let best = pool[0];
  let bestDist = Math.abs(best - startOffset);
  for (const c of pool) {
    const d = Math.abs(c - startOffset);
    if (d < bestDist) { best = c; bestDist = d; }
  }
  return { start: best, end: best + quote.length };
}

// Wrap a (possibly multi-node) range in one <mark> per intersecting text node,
// since surroundContents() rejects ranges that partially select non-text nodes.
// `note` (#2/#3), when present, gets a small dot badge + hover tooltip on the
// first fragment only, so a multi-node highlight doesn't repeat it. `resolved`
// (#3) de-emphasizes the anchor instead of hiding it.
function wrapRange(range, id, color, note, resolved) {
  const nodes = [];
  const walker = document.createTreeWalker(contentEl, NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => (range.intersectsNode(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT),
  });
  let node;
  while ((node = walker.nextNode())) nodes.push(node);

  let markedFirst = false;
  nodes.forEach((textNode) => {
    const nodeRange = document.createRange();
    nodeRange.selectNodeContents(textNode);
    if (textNode === range.startContainer) nodeRange.setStart(textNode, range.startOffset);
    if (textNode === range.endContainer) nodeRange.setEnd(textNode, range.endOffset);
    if (nodeRange.collapsed) return;
    const mark = document.createElement('mark');
    mark.className = 'rmd-highlight' + (resolved ? ' resolved' : '');
    mark.dataset.markId = id;
    mark.dataset.color = color;
    if (note && !markedFirst) {
      mark.classList.add('has-note');
      mark.title = note;
      markedFirst = true;
    }
    nodeRange.surroundContents(mark);
  });
}

// `hidden` (#3) marks are still anchor-resolved here — so orphan detection
// stays accurate even while a resolved thread's visibility is toggled off —
// just not wrapped/rendered into the DOM.
function applyMarks(marksJSON) {
  let list = [];
  try { list = JSON.parse(marksJSON) || []; } catch { list = []; }
  clearHighlights();
  const orphaned = [];
  for (const m of list) {
    const offsets = resolveAnchor(m.anchor);
    if (!offsets) { orphaned.push(m.id); continue; }
    const range = rangeFromOffsets(offsets.start, offsets.end);
    if (!range) { orphaned.push(m.id); continue; }
    if (!m.hidden) wrapRange(range, m.id, m.color, m.note, m.resolved);
  }
  post('marksApplied', orphaned);
}

// Report the current selection to Swift so it can show a color-swatch
// popover. Fires after mouseup (mouse selection) or shift/arrow keyup
// (keyboard selection); a collapsed/empty selection posts null to dismiss.
function reportSelection() {
  // Marks anchor by character offset into the RENDERED DOM; against diff rows
  // they would resolve to the wrong text, so no selection is reported here.
  if (diffMode) return;
  const sel = window.getSelection();
  if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
    // A plain click (collapsed) inside an existing highlight must not dismiss:
    // markClicked is about to open the edit popover (with the no-color remove
    // swatch), and posting null here would race-hide it.
    const n = sel && sel.anchorNode;
    const el = n && (n.nodeType === 1 ? n : n.parentElement);
    if (el && el.closest && el.closest('mark.rmd-highlight')) return;
    post('textSelected', null);
    return;
  }
  const range = sel.getRangeAt(0);
  if (!contentEl.contains(range.commonAncestorContainer)) { post('textSelected', null); return; }
  const offsets = offsetsFromRange(range);
  if (!offsets) { post('textSelected', null); return; }
  const text = contentEl.textContent;
  // Derive the quote from textContent, not sel.toString() — the latter inserts
  // "\n" at block boundaries, so a selection spanning two blocks would yield a
  // quote that isn't a substring of textContent and orphan on the next resolve.
  const quote = text.slice(offsets.start, offsets.end);
  if (!quote.trim()) { post('textSelected', null); return; }
  const rect = range.getBoundingClientRect();
  post('textSelected', {
    quote,
    prefix: text.slice(Math.max(0, offsets.start - 32), offsets.start),
    suffix: text.slice(offsets.end, offsets.end + 32),
    startOffset: offsets.start,
    rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height },
  });
}

document.addEventListener('mouseup', () => setTimeout(reportSelection, 0));
document.addEventListener('keyup', (e) => {
  if (e.shiftKey || e.key.startsWith('Arrow')) setTimeout(reportSelection, 0);
});

// Clicking an existing highlight offers remove/change-color instead of
// creating a new one.
contentEl.addEventListener('click', (e) => {
  const mark = e.target.closest && e.target.closest('mark.rmd-highlight');
  if (!mark) return;
  e.preventDefault();
  e.stopPropagation();
  const rect = mark.getBoundingClientRect();
  post('markClicked', {
    id: mark.dataset.markId,
    rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height },
  });
}, true);

// ---- Find in page ----
//
// Find has its OWN filtered text base — NOT contentEl.textContent and NOT the
// marks walker. It excludes heading anchors, code-copy buttons, inline SVG
// (Mermaid), and KaTeX, so invisible/injected text is never counted or wrapped.
// Kept entirely separate from the marks anchoring (resolveAnchor / rangeFromOffsets),
// which needs the polluted-but-consistent text and must not be touched.

// `.sr-only` covers the footnote extension's visually-hidden "Footnotes" <h2>:
// hidden to the reader, but a real text node, so an unfiltered search for
// "footnotes" would match it and inflate the count.
const FIND_EXCLUDE = '.anchor, .copy-btn, .mm-controls, svg, .katex, .sr-only';
let findMatches = [];   // one entry per occurrence: an array of its <mark> elements
let findFocus = 0;      // index of the .current occurrence
let findQuery = '';     // the live query, so refind() can rebuild after a re-render

// [{ node, start, end }] over the visible prose, plus the concatenated string.
function findTextSegments() {
  const walker = document.createTreeWalker(contentEl, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) =>
      n.parentElement && !n.parentElement.closest(FIND_EXCLUDE)
        ? NodeFilter.FILTER_ACCEPT
        : NodeFilter.FILTER_REJECT,
  });
  const segments = [];
  let text = '';
  let node;
  while ((node = walker.nextNode())) {
    const len = node.textContent.length;
    segments.push({ node, start: text.length, end: text.length + len });
    text += node.textContent;
  }
  return { segments, text };
}

// Wrap one occurrence spanning [mStart, mEnd) in <mark class="rmd-find">, one per
// intersecting text node. Returns the created <mark> elements. Each surroundContents
// is confined to a single text node, so it can never partially select an element
// and can never throw.
function wrapFindMatch(segments, mStart, mEnd) {
  const marks = [];
  for (const seg of segments) {
    if (seg.end <= mStart || seg.start >= mEnd) continue; // no overlap
    const from = Math.max(mStart, seg.start) - seg.start;
    const to = Math.min(mEnd, seg.end) - seg.start;
    const range = document.createRange();
    range.setStart(seg.node, from);
    range.setEnd(seg.node, to);
    const mark = document.createElement('mark');
    mark.className = 'rmd-find';
    range.surroundContents(mark);
    marks.push(mark);
  }
  return marks;
}

// Mirror of clearHighlights() for find marks. Forgets the *marks*, not the
// *position*: findFocus and findQuery survive so refind() can restore the user's
// current match after the DOM is rebuilt.
function clearFind() {
  contentEl.querySelectorAll('mark.rmd-find').forEach((mark) => {
    const parent = mark.parentNode;
    if (!parent) return;
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  });
  findMatches = [];
}

function setCurrentFind(i, scroll) {
  const prev = findMatches[findFocus];
  if (prev) prev.forEach((m) => m.classList.remove('current'));
  findFocus = i;
  const cur = findMatches[i];
  if (!cur || !cur.length) return;
  cur.forEach((m) => m.classList.add('current'));
  if (scroll) cur[0].scrollIntoView({ block: 'center' });
}

// `wantFocus` is the occurrence to make current; `scroll` says whether to bring it
// into view. A user-initiated find passes (0, true); a re-application after the DOM
// was rebuilt passes (findFocus, false) so the viewport and the counter hold still.
function applyFindQuery(query, wantFocus, scroll) {
  clearFind();
  findQuery = query || '';
  const q = findQuery.toLowerCase();
  if (!q) { findFocus = 0; post('findResult', { count: 0, index: 0 }); applyFocusDim(); return; }

  const { segments, text } = findTextSegments();
  const lower = text.toLowerCase();
  const occurrences = [];
  let idx = lower.indexOf(q);
  while (idx !== -1) {
    occurrences.push([idx, idx + q.length]);
    idx = lower.indexOf(q, idx + q.length); // non-overlapping
  }
  if (!occurrences.length) { findFocus = 0; post('findResult', { count: 0, index: 0 }); applyFocusDim(); return; }

  // Wrap last-to-first so wrapping a later occurrence can't invalidate the
  // offsets of an earlier one that shares a text node.
  const byOccurrence = new Array(occurrences.length);
  for (let i = occurrences.length - 1; i >= 0; i--) {
    byOccurrence[i] = wrapFindMatch(segments, occurrences[i][0], occurrences[i][1]);
  }
  findMatches = byOccurrence;
  // Clamp: an edited file may now hold fewer matches than before the re-render.
  const focus = Math.min(Math.max(wantFocus, 0), findMatches.length - 1);
  setCurrentFind(focus, scroll);
  post('findResult', { count: findMatches.length, index: focus });
  applyFocusDim();
}

function findStep(forward) {
  const n = findMatches.length;
  if (!n) { post('findResult', { count: 0, index: 0 }); return; }
  const next = ((findFocus + (forward ? 1 : -1)) % n + n) % n;
  setCurrentFind(next, true);
  post('findResult', { count: n, index: next });
}

// Signal readiness so Swift can flush any pending document.
post('ready', true);
