// Landing feature cards, docs feature rows, keyboard shortcuts, CLI commands,
// and architecture notes — all sourced from README.md so the site stays in
// sync with the app's own description.

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
    title: "Remote SSH folders",
    body: 'Add a folder from any VPS. Reader.md <code class="tok">rsync</code>s it read-only into a local cache and shows it like any root — reusing your <code class="tok">~/.ssh</code> config, storing no credentials.',
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
    body: 'Open, filter, find, navigate history, resize the column, and export — all without leaving the keyboard. Full map in the <a href="/docs#shortcuts">docs</a>.',
  },
];

// --- Docs: feature table rows -------------------------------------------------
export interface FeatureRow {
  name: string;
  body: string; // HTML
}

export const featureRows: FeatureRow[] = [
  {
    name: "Open anything",
    body: 'A single <code class="tok">.md</code> file (⌘O or double-click in Finder), whole folders, or a mix. Set Reader.md as your default markdown handler.',
  },
  {
    name: "Multi-folder browser",
    body: "Add any number of roots (multi-select or drag folders onto the window). Each is a collapsible section with hover-to-reveal actions; roots reorder by drag.",
  },
  {
    name: "Remote SSH folders",
    body: 'Add a folder from a VPS: Reader.md <code class="tok">rsync</code>s it read-only into a local cache. Auto-syncs on launch, manual re-sync, edit-in-place, and a cloud badge with sync/error state. Reuses your <code class="tok">~/.ssh</code> config — no credentials stored.',
  },
  {
    name: "Quick open & find",
    body: "⌘P fuzzy file switcher across all roots, ⌘F live tree filter, and ⇧⌘F native in-page find with match highlighting (⌘G / ⇧⌘G for next/prev).",
  },
  {
    name: "Outline",
    body: "Collapsible right pane (⇧⌘B) with a sliding accent rail marker and scrollspy.",
  },
  {
    name: "Typography",
    body: 'Font size (⌘+ / ⌘− / ⌘0) and a narrow / wide / full-width reading column (⇧⌘\\), both persisted.',
  },
  {
    name: "Rendering",
    body: "Syntax highlighting, Mermaid, and LaTeX math via bundled JS engines. YAML frontmatter renders as a clean key/value table. Code copy buttons, image click-to-zoom lightbox, and hover heading anchors.",
  },
  {
    name: "Reading themes",
    body: "Standard, Editorial, Terminal, and GitHub — each with its own typography, accent, and syntax highlighting. Resume where you stopped in long documents.",
  },
  {
    name: "Liquid Glass chrome",
    body: 'On macOS 26 (Tahoe) the toolbar, sidebar, outline, find bar, and quick-open palette read as Liquid Glass; on 13–15 they fall back to translucent <code class="tok">NSVisualEffectView</code> material. Collapsible + resizable sidebar (⌘B, width persisted).',
  },
  {
    name: "Live reload & export",
    body: "The open file re-renders (scroll preserved) and the tree refreshes on disk changes. Export to PDF (⌘E), manual reload (⌘R), dark mode, and Sparkle auto-update.",
  },
];

// --- Docs: keyboard shortcuts -------------------------------------------------
export interface Shortcut {
  action: string;
  keys: string;
}

export const shortcuts: Shortcut[] = [
  { action: "Open file", keys: "⌘O" },
  { action: "Quick open", keys: "⌘P" },
  { action: "Add folder", keys: "⇧⌘A" },
  { action: "Add remote folder", keys: "⌥⌘A" },
  { action: "Filter files", keys: "⌘F" },
  { action: "Find in page", keys: "⇧⌘F" },
  { action: "Find next / previous", keys: "⌘G / ⇧⌘G" },
  { action: "Back / forward", keys: "⌘[ / ⌘]" },
  { action: "Toggle sidebar", keys: "⌘B" },
  { action: "Toggle outline", keys: "⇧⌘B" },
  { action: "Text bigger / smaller / reset", keys: "⌘+ / ⌘− / ⌘0" },
  { action: "Column width", keys: "⇧⌘\\" },
  { action: "Export PDF", keys: "⌘E" },
  { action: "Reload", keys: "⌘R" },
];

// A compact subset for the landing "keyboard & CLI" strip.
export const shortcutsHighlight: Shortcut[] = [
  { keys: "⌘P", action: "Quick open" },
  { keys: "⌘F", action: "Filter files" },
  { keys: "⇧⌘F", action: "Find in page" },
  { keys: "⌘B", action: "Toggle sidebar" },
  { keys: "⌘E", action: "Export PDF" },
];

// --- CLI commands -------------------------------------------------------------
export interface CliCommand {
  cmd: string;
  note: string;
}

export const cliCommands: CliCommand[] = [
  { cmd: "reader <file.md>", note: "open a markdown file" },
  { cmd: "reader <folder>", note: "add a folder to the sidebar" },
  { cmd: "reader .", note: "add the current directory" },
  { cmd: "reader remote me@vps:/srv/docs", note: "add a remote (SSH) folder" },
  { cmd: "reader ls", note: "list configured folders" },
  { cmd: "reader rm <name|path>", note: "remove a folder" },
  { cmd: "git diff | reader -", note: "open piped markdown" },
];

// --- Docs: architecture cards -------------------------------------------------
export interface ArchCard {
  name: string;
  hue: number | null;
  body: string; // HTML
}

export const archCards: ArchCard[] = [
  {
    name: "SwiftUI shell",
    hue: 260,
    body: 'The window\'s native toolbar over <code class="tok">ContentView</code> — a resizable/collapsible sidebar, the content pane, and a collapsible outline; overlays host the find bar and quick-open palette.',
  },
  {
    name: "AppState",
    hue: 260,
    body: 'An <code class="tok">ObservableObject</code> (<code class="tok">@MainActor</code>) holding roots, selection, theme, search, outline, typography, layout, history, and find/export triggers; persists to <code class="tok">UserDefaults</code>.',
  },
  {
    name: "RemoteSync",
    hue: 205,
    body: 'A remote folder is <code class="tok">rsync</code>\'d read-only into a stable local cache dir that registers as an ordinary root. Credentials come from your <code class="tok">~/.ssh</code> config/keys — none are stored in-app.',
  },
  {
    name: "MarkdownWebView",
    hue: 205,
    body: 'An <code class="tok">NSViewRepresentable</code> around <code class="tok">WKWebView</code>. Swift pushes markdown / theme / font settings; JS posts the outline, active heading, word count, scroll progress, and link clicks back. Bundled marked, highlight.js, KaTeX, and Mermaid — no network.',
  },
  {
    name: "GlassPanel / FolderWatcher",
    hue: null,
    body: 'Chrome surfaces use Apple\'s Liquid Glass on macOS 26, with an <code class="tok">NSVisualEffectView</code> fallback on 13–15. An FSEvents subtree watcher drives debounced live reload.',
  },
];
