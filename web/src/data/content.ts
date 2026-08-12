// Landing-page copy only: the highlight cards and the compact shortcut strip,
// both condensed from the repo's docs/features.md so the site stays in sync with
// the app's own description.
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
  { keys: "⌘E", action: "Export PDF" },
];
