/* global marked, hljs, renderMathInElement, mermaid */
// Bridge between the SwiftUI host and the markdown web view.

const contentEl = document.getElementById('content');
let mermaidCounter = 0;
let currentDir = '';

function isDark() { return document.documentElement.classList.contains('dark'); }

function post(name, body) {
  if (window.webkit && window.webkit.messageHandlers[name]) {
    window.webkit.messageHandlers[name].postMessage(body);
  }
}

function initMermaid() {
  mermaid.initialize({ startOnLoad: false, theme: isDark() ? 'dark' : 'default', securityLevel: 'loose' });
}

marked.setOptions({ gfm: true, breaks: false });

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

  loadMarkdown(text, dir) {
    render(text, dir, false);
  },

  reloadMarkdown(text, dir) {
    render(text, dir, true);
  },

  scrollToHeading(id) {
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  },

  setFontScale(scale) {
    document.documentElement.style.setProperty('--content-size', `${16 * scale}px`);
  },

  setWide(wide) {
    document.documentElement.style.setProperty('--content-width', wide ? '1080px' : '760px');
  },

  applyMarks(marksJSON) {
    applyMarks(marksJSON);
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

async function render(text, dir, keepScroll) {
  const prevScroll = keepScroll ? window.scrollY : 0;
  window.__lastMarkdown = text;
  currentDir = dir || '';

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

  window.scrollTo(0, prevScroll);
  reportActiveHeading();
  reportProgress();
  post('rendered', true);
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
      container.innerHTML = svg;
    } catch (err) {
      container.innerHTML = `<pre class="error-msg">Mermaid error: ${escapeHtml(String(err.message || err))}</pre>`;
      const orphan = document.getElementById(`d${id}`);
      if (orphan) orphan.remove();
    }
    block.closest('pre').replaceWith(container);
  }
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
    entries.push({ id: h.id, text: h.textContent, level: Number(h.tagName[1]) });
  });
  post('toc', entries);
}

function reportActiveHeading() {
  const headings = contentEl.querySelectorAll('h1,h2,h3,h4');
  if (!headings.length) return;
  let activeId = headings[0].id;
  for (const h of headings) {
    if (h.getBoundingClientRect().top <= 100) activeId = h.id;
    else break;
  }
  post('activeHeading', activeId);
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
  const sel = window.getSelection();
  if (!sel || sel.isCollapsed || sel.rangeCount === 0) { post('textSelected', null); return; }
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

// Signal readiness so Swift can flush any pending document.
post('ready', true);
