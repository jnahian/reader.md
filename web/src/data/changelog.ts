// Release history — mirrors Sources/ReaderMd/Resources/docs/CHANGELOG.md,
// grouped into the changelog design's ADDED / IMPROVED / FIXED buckets.
// `items` are HTML strings (rendered with set:html) so lead-ins can be bold.

export type Tag = "ADDED" | "IMPROVED" | "FIXED";

export interface ChangeGroup {
  tag: Tag;
  items: string[];
}

export interface Release {
  version: string;
  date: string;
  badge?: "LATEST" | "INITIAL";
  intro?: string;
  groups: ChangeGroup[];
}

export const releasesLog: Release[] = [
  {
    version: "1.10.0",
    date: "Jul 14, 2026",
    badge: "LATEST",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Resume where you stopped</strong> — reopening a long file returns you to the place you left off. A document you barely started, or one you finished, still opens at the top.",
          "<strong>A GitHub reading theme</strong> — the content pane can now wear GitHub's palette, fonts, and code colours, alongside Standard, Editorial, and Terminal.",
        ],
      },
    ],
  },
  {
    version: "1.9.0",
    date: "Jul 13, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>New sidebar shortcuts</strong> — <code class=\"tok\">⌘B</code> toggles the file sidebar and <code class=\"tok\">⇧⌘B</code> the outline, matching the rest of the Mac.",
          "<strong>A close button on the open document</strong> — a floating × in the top-right corner, the visible form of <code class=\"tok\">⌘W</code>.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "The empty screen is clickable — open a file, add a folder, quick-open, or jump to the sidebar filter by clicking the row.",
          "The sidebar reveals what you open, expanding folders down to the file instead of leaving it hidden in a collapsed tree.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "The × on a Recents row removes the entry again (it had briefly closed the file instead).",
        ],
      },
    ],
  },
  {
    version: "1.8.0",
    date: "Jul 13, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Full-width reading column</strong> — three widths (Narrow, Wide, Full Width) instead of a narrow/wide toggle. Full Width stops wide tables and code blocks scrolling sideways; <code class=\"tok\">⇧⌘\\</code> cycles them.",
        ],
      },
    ],
  },
  {
    version: "1.7.1",
    date: "Jul 13, 2026",
    groups: [
      {
        tag: "IMPROVED",
        items: [
          "<strong>You can close a document now</strong> — <code class=\"tok\">⌘W</code> closes the open file and leaves the window up. File → Close and the sidebar / Recents context menus do the same.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<code class=\"tok\">reader</code> opened a new window on every invocation instead of reusing the one already open.",
        ],
      },
    ],
  },
  {
    version: "1.7.0",
    date: "Jul 12, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>A <code class=\"tok\">reader</code> command line tool</strong> — open a file, add a folder, add a remote, or pipe markdown straight into the app from your terminal.",
          "<strong>Add Remote Folder… in the File menu</strong>, reachable with the sidebar collapsed. New shortcuts: <code class=\"tok\">⇧⌘A</code> adds a folder, <code class=\"tok\">⌥⌘A</code> a remote.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "The window uses the native macOS toolbar, so on macOS 26 it reads as real Liquid Glass with capsule controls.",
          "Update prompts now show what changed instead of a blank pane.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "The find field is disabled when no document is open, and <code class=\"tok\">⌘F</code> focuses it reliably.",
        ],
      },
    ],
  },
  {
    version: "1.6.0",
    date: "Jul 10, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Find in Page</strong> — highlights every match, shows a live “N of M” count, and steps through matches with <code class=\"tok\">⌘G</code> / <code class=\"tok\">⇧⌘G</code>.",
          "<strong>Reading themes</strong> — Standard, Editorial, or Terminal, each with its own typography, accent, and syntax highlighting, persisted across launches.",
          "<strong>Footnotes</strong> render as a linked, styled section at the end of the document.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "Links follow your macOS accent colour in the Standard theme, updating live when you change it or switch light/dark.",
          "The topbar follows macOS Preview — the find bar now lives in the topbar. Find in Page moved to <code class=\"tok\">⌘F</code>; Filter Files to <code class=\"tok\">⇧⌘F</code>.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "Drag and drop now works with a document open, and shows a drop target.",
          "The find bar and quick-open fields take keyboard focus immediately, instead of needing a click first.",
        ],
      },
    ],
  },
  {
    version: "1.5.0",
    date: "Jul 8, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Remote (SSH) folders</strong> — add a remote folder and Reader.md syncs it read-only to a local cache via <code class=\"tok\">rsync</code>.",
          "<strong>Help menu</strong> — FAQ, a keyboard-shortcut cheatsheet (<code class=\"tok\">⌘/</code>), and release notes.",
        ],
      },
    ],
  },
  {
    version: "1.4.0",
    date: "Jul 8, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Annotations</strong> — highlight a selection and attach a note, with resolvable comment threads.",
          "<strong>Liquid Glass topbar buttons</strong> on macOS 26 (Tahoe).",
        ],
      },
      {
        tag: "FIXED",
        items: ["Markup popover UX — positioning, alignment, and click handling."],
      },
    ],
  },
  {
    version: "1.3.2",
    date: "Jul 7, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Auto-update via Sparkle</strong>, delivered as a DMG installer.",
          "<strong>About panel</strong> with version info.",
        ],
      },
      {
        tag: "IMPROVED",
        items: ["YAML frontmatter renders as a clean key/value table."],
      },
    ],
  },
  {
    version: "1.2.0",
    date: "Jul 7, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "Drop files onto the window body; manage recent files.",
          "Open single files, drag-and-drop, and register as the default markdown handler.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "Root folders collapse in the sidebar by default; scan hidden folders and reorder roots by drag.",
        ],
      },
    ],
  },
  {
    version: "1.0.0",
    date: "Jul 6, 2026",
    badge: "INITIAL",
    intro:
      "The first native macOS build — a SwiftUI shell around a bundled WKWebView renderer.",
    groups: [
      {
        tag: "ADDED",
        items: [
          "Mermaid, LaTeX, and syntax highlighting via bundled JS engines — fully offline.",
          "Live reload, outline, quick open, and PDF export.",
        ],
      },
    ],
  },
];
