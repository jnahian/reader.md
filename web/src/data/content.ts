// Landing-page copy only: the highlight cards, the compact shortcut strip, and
// the FAQ accordion — condensed from the repo's docs/features.md and docs/faq.md
// so the site stays in sync with the app's own description.
//
// The docs pages themselves are no longer mirrored here — /docs renders the
// repo's docs/*.md directly (see src/content.config.ts).

// --- Landing: highlight cards (glyph + blurb) ---------------------------------
export interface HighlightCard {
  glyph: string;
  hue: number | null; // oklch hue for the icon tint; null = neutral white
  title: string;
  body: string; // HTML
}

export const highlights: HighlightCard[] = [
  {
    glyph: "☁",
    hue: 205,
    title: "Remote & cloned folders",
    body: 'Add a folder from any VPS or a git repository by URL. Reader.md <code class="tok">rsync</code>s or <code class="tok">git clone</code>s it read-only into a local cache and shows it like any root — reusing the SSH and git credentials you already have, storing none.',
  },
  {
    glyph: "∑",
    hue: 260,
    title: "Diagrams & math, for real",
    body: "Bundled Mermaid, KaTeX, and highlight.js render diagrams, LaTeX, and code with no network access. The one thing a native view can't do, done right.",
  },
  {
    glyph: "⌘",
    hue: 300,
    title: "Multi-folder & quick open",
    body: 'Add any number of roots, drag to reorder, and jump anywhere with a <code class="tok">⌘P</code> fuzzy switcher that spans every folder at once.',
  },
  {
    glyph: "◈",
    hue: null,
    title: "Liquid Glass chrome",
    body: 'On macOS 26 the toolbar, sidebar, outline, and palettes read as real Liquid Glass — with an automatic <code class="tok">NSVisualEffectView</code> fallback on 13–15.',
  },
  {
    glyph: "↻",
    hue: null,
    title: "Live reload",
    body: "An FSEvents watcher re-renders the open file with scroll preserved and refreshes the tree the moment anything changes on disk.",
  },
  {
    glyph: "⇧",
    hue: null,
    title: "Keyboard-first",
    body: 'Open, filter, find, navigate history, resize the column, and export — all without leaving the keyboard. Full map in the <a href="/docs/features#keyboard-shortcuts">docs</a>.',
  },
];

// --- Landing: keyboard shortcuts -------------------------------------------------
export interface Shortcut {
  action: string;
  keys: string;
}

// A compact subset for the landing "keyboard & CLI" strip.
export const shortcutsHighlight: Shortcut[] = [
  { keys: "⌘P", action: "Quick open" },
  { keys: "⌘F", action: "Find in page" },
  { keys: "⇧⌘F", action: "Filter files" },
  { keys: "⌘B", action: "Toggle sidebar" },
  { keys: "⌥⌘F", action: "Focus mode" },
  { keys: "⌘E", action: "Export PDF" },
];

// --- Landing: FAQ accordion ------------------------------------------------
export interface Faq {
  q: string;
  a: string; // HTML
}

// The six questions people ask before downloading, condensed from the "Before
// you install" section of docs/faq.md. The rest of that page stays there.
export const faqsHighlight: Faq[] = [
  {
    q: "Is it really free?",
    a: 'MIT-licensed and open source. No account, no trial, no paid tier — the <a href="https://github.com/jnahian/reader.md">repository</a> is the whole thing.',
  },
  {
    q: "Why does macOS say it can't check it for malicious software?",
    a: 'The app is ad-hoc signed but not notarized, so the first launch is gated. Right-click → <strong>Open</strong> once, or run <code class="tok">xattr -dr com.apple.quarantine</code> on it. <a href="/docs/install#clearing-quarantine">Details</a>.',
  },
  {
    q: "Does it need macOS 26?",
    a: "No — macOS 13 or later. Liquid Glass chrome lights up on macOS 26 (Tahoe); 13 through 15 get the <code class=\"tok\">NSVisualEffectView</code> fallback automatically, with nothing to configure.",
  },
  {
    q: "Can I edit files in it?",
    a: 'No. Reader.md reads, and hands editing to the editor you already use — <code class="tok">⇧⌘E</code> opens the current document there, and the folder watcher re-renders on save, so the two side by side behave like a live preview.',
  },
  {
    q: "Does it phone home?",
    a: "No. Mermaid, KaTeX, and highlight.js are bundled, so a document renders identically with the network off. The only outbound request is the update check.",
  },
  {
    q: "Does it work on Intel Macs?",
    a: 'The binary is arm64-only, so both the app and its updates are offered to Apple silicon only. <a href="/docs/install#requirements">Requirements</a>.',
  },
];
