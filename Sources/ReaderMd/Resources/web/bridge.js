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
};

// ---- Rendering ----

async function render(text, dir, keepScroll) {
  const prevScroll = keepScroll ? window.scrollY : 0;
  window.__lastMarkdown = text;
  currentDir = dir || '';

  contentEl.innerHTML = marked.parse(text);

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

// Signal readiness so Swift can flush any pending document.
post('ready', true);
