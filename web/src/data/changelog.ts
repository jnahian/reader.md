// Release history — mirrors Sources/ReaderMd/Resources/docs/CHANGELOG.md,
// grouped into the changelog design's ADDED / IMPROVED / FIXED buckets.
// `items` are HTML strings (rendered with set:html) so lead-ins can be bold.
//
// Pushing a change here to `main` publishes the site: this file is under `web/`,
// which is what Cloudflare's build watch paths match. See web/DEPLOYMENT.md.

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
    version: "1.19.0",
    date: "Aug 28, 2026",
    badge: "LATEST",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Focus mode</strong> (\u2325\u2318F) \u2014 hides the sidebar, outline and toolbar, goes fullscreen, and dims every section but the one you're reading. Each of the four pieces can be switched off in Settings; \u238b or \u2325\u2318F leaves, and so does leaving fullscreen any other way \u2014 the green traffic-light button. The hidden toolbar slides back on a top-edge hover, or on \u2318F, without leaving the mode. Settings also sets how wide the lit region is \u2014 every heading, or only headings down to H3, H2 or H1, so a section keeps its subsections lit \u2014 and how far the rest dims.",
          "<strong>Keyboard navigation</strong> \u2014 \u21e5 now moves focus through the sidebar rows, the outline, the empty-state hints and the toolbar, each showing a focus ring as it takes focus; they were clickable and nothing else before. \u2423 has always pressed whatever has focus, and \u23ce now does the same, so tabbing to a file and pressing Return opens it. Requires <strong>System Settings \u25b8 Keyboard \u25b8 Keyboard navigation</strong>, which macOS owns.",
          "<strong>Share a PDF</strong> \u2014 the export button in the toolbar is now a menu. Beside <strong>Export as PDF\u2026</strong> it holds <strong>Share PDF\u2026</strong>, which renders the same PDF and opens the system share sheet on it \u2014 AirDrop, Mail, Messages, and any share extension you have installed. It's also in <strong>File \u25b8 Share PDF\u2026</strong> and in \u2318P. The shared PDF uses the default layout from <strong>Settings \u25b8 Editing &amp; Export</strong>, and arrives named after the document, so AirDropping a <code>README.md</code> lands a <code>README.pdf</code> on the other machine.",
          "<strong>Share the markdown file itself</strong> \u2014 the same menu offers <strong>Share Markdown File\u2026</strong>, which sends the <code>.md</code> rather than a rendered PDF. Nothing is rendered, so it opens the share sheet at once, and it stays available while the diff view is up, where there is no rendered document to export.",
        ],
      },
    ],
  },
  {
    version: "1.18.2",
    date: "Aug 26, 2026",
    groups: [
      {
        tag: "FIXED",
        items: [
          "<strong>Tooltips no longer appear on their own, or name the wrong control</strong> — a tooltip asked the system for the part of its control still on screen and was answered with the whole sidebar or toolbar, so a pointer resting anywhere in that panel counted as resting on every control in it. Opening a file relaid the panel out and put up to five unrelated bubbles on screen at once, and pointing at a file in the sidebar named the \u00d7 beside it instead of the file, whose own tooltip never arrived. A bubble now belongs to the control actually under the pointer.",
        ],
      },
    ],
  },
  {
    version: "1.18.1",
    date: "Aug 16, 2026",
    groups: [
      {
        tag: "IMPROVED",
        items: [
          "<strong>The update prompt's dismiss button now reads \"Remind Later\"</strong> — instead of \"Remind Me Later\". Other languages keep their own wording.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>Check for Updates… can't be left doing nothing</strong> — Sparkle drops the request whenever it still believes it's showing an update whose window is already gone, and says so only in the system log, so the menu item would have answered a click with no window and no error. <strong>Reader.md ▸ Check for Updates…</strong> now recognises that state and starts over rather than letting the click fall through.",
        ],
      },
    ],
  },
  {
    version: "1.18.0",
    date: "Aug 13, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Links in the About panel</strong> — <strong>Website</strong>, <strong>Docs</strong>, and <strong>Report an Issue</strong>, clickable straight from <strong>Reader.md ▸ About Reader.md</strong>. The Help menu carries the same destinations, with <strong>Reader.md Website</strong> and <strong>Documentation</strong> joining the two GitHub items already there.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>No more tooltip on launch, or on switching back to Reader.md</strong> — a window that opened under a stationary pointer counted as a hover, so whichever control happened to land under the cursor — usually the toolbar's sidebar toggle — put its bubble on screen unprompted, and ⌘-tabbing back with the pointer parked did it again. A bubble now waits for the pointer to actually be moved onto a control.",
          "<strong>Git badges on a folder reached through a symlink</strong> — a repository added as <code class=\"tok\">/tmp/notes</code>, or through a link to another volume, showed no <code class=\"tok\">M</code> · <code class=\"tok\">A</code> · <code class=\"tok\">?</code> badges at all. The sidebar looks them up under the resolved path the folder scan returns, and the badge map was keyed only under the path you added.",
          "<strong><code class=\"tok\">reader ls</code> printed nothing useful for a cloned repository</strong> — just a bare <code class=\"tok\">:</code> where its origin should be. Cloned remotes arrived after that listing was written and never reached it; it now shows the clone URL.",
          "<strong><code class=\"tok\">brew uninstall --zap</code> left your annotations behind</strong> — highlights, notes, and cached remote folders live under the app's name rather than its bundle id, and only the bundle-id paths were being removed, so a zap reported success and cleaned up nothing of yours.",
        ],
      },
    ],
  },
  {
    version: "1.17.0",
    date: "Aug 12, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Settings window (⌘,)</strong> — appearance, reading theme, text size, canvas width, the external editor, and the default PDF export layout in one place. Mostly a second way into preferences the toolbar and menus already carry; the default PDF layout, clearing the external editor, and picking an appearance mode directly rather than cycling to it live only here.",
          "<strong>Clear the external editor</strong> — from Settings. Previously the only way to unset one was to uninstall it.",
          "<strong>Settings in Quick Open</strong> — type <code class=\"tok\">&gt;settings</code> in the ⌘P palette to open the window, alongside every other preference the palette already offered.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "<strong>The Layout popup in the ⌘E save panel is now a per-export choice</strong> — it used to overwrite your default, so exporting once as Continuous quietly changed every later export. The default now lives in Settings ▸ Editing &amp; Export.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>⌘↩ and ⇧⌘↩ step through find matches</strong> — as the search field's tooltips and the shortcuts page have always said. Neither was actually wired up; only plain ↩ moved to the next match.",
        ],
      },
    ],
  },
  {
    version: "1.16.1",
    date: "Aug 11, 2026",
    groups: [
      {
        tag: "FIXED",
        items: [
          "<strong>The × on a Favorites row works again</strong> — as does dragging one to reorder. The row's tooltip covered it with an invisible layer that swallowed the click, so unpinning did nothing and the row wouldn't move. Recents was unaffected, which is why only Favorites looked stuck.",
          "<strong>Sidebar × tooltips no longer get crossed</strong> — removing the last file from Recents or Favorites collapses that whole section, so the row beneath slid up under a pointer that never moved and kept the vanished row's label — which is how a Favorites × came to read \"Remove from Recents\". The row under the pointer is now re-checked whenever the sidebar re-lays out.",
        ],
      },
    ],
  },
  {
    version: "1.16.0",
    date: "Aug 11, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Page-by-page PDF export</strong> — the ⌘E save dialog has a Layout control. <strong>Page by Page</strong> (the new default) paginates the document onto real pages at your system paper size, keeping diagrams and images whole across page breaks, wrapping long code lines rather than cutting them off at the page edge, and painting the page in the reading theme's color. <strong>Continuous</strong> keeps the old single long page. Links stay clickable either way, and your last choice is remembered.",
          "<strong>Step find matches from the toolbar</strong> — the find field now has up/down chevrons beside the \"N of M\" count that jump to the previous/next match, and ⌘↩ / ⇧⌘↩ step the matches as aliases for ⌘G / ⇧⌘G — so you can walk the results without leaving the search field.",
          "<strong>Favorites in the sidebar</strong> — pin the files you keep coming back to and they sit in a <strong>FAVORITES</strong> section between Recents and your folders, in the order you arranged them. Star a file from its hover control in the tree, from any file's context menu, with ⌘D for the open document, or from the ⌘P palette; drag to reorder, hover <strong>×</strong> to unpin. Recents churns as you read; Favorites stay until you remove them, and a pinned file drops out of Recents so opening it never looks like it left the list.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "<strong>Canvas width has its own topbar button</strong> — the width picker (formerly \"Column Width\") moved out of the text-size menu into a dedicated ↔ button, and is now called <strong>Canvas Width</strong> everywhere. Wide is the new default for fresh installs; an existing choice is kept.",
          "<strong>Picking what to diff against is a popover now</strong> — the topbar's scope control replaces its pull-down menu. It names the current scope on the button, groups the branches under their own scrolling section, filters them by name in repos with many branches, and opens scrolled to the branch you're comparing against.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>Opening a folder no longer shows a blank pane</strong> — file-URL opens (<code>open -a Reader.md.app ~/docs</code>, dropping a folder on the app icon, <code>reader open</code>) and Recents taps now route directories into the sidebar as roots the same way <strong>Add Folder</strong> does, and the sidebar reveals itself if it was collapsed. Stale folder paths already in Recents or Favorites are dropped on launch.",
          "<strong>Links to files with spaces in the name open again</strong> — a relative link such as <code>[notes](&lt;My Note.md&gt;)</code> reaches the app percent-encoded; it now resolves to the real file instead of opening an empty document.",
          "<strong>Tooltips no longer stay on screen after you click</strong> — a hover bubble hung around once the click landed, and one that opened a menu or popover could strand it there entirely. Clicking now dismisses it.",
        ],
      },
    ],
  },
  {
    version: "1.15.0",
    date: "Aug 1, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Clone a git repository as a folder</strong> — the Add Remote sheet now offers <strong>Git</strong> alongside SSH: paste a clone URL and Reader.md clones it read-only into a local cache, fast-forwarding it on every launch the same way SSH folders re-sync. It uses your existing git credentials and never prompts, so a repository you can't authenticate to fails with git's own message instead of hanging.",
          "<strong>Diff against a branch</strong> — the diff scope control is now a menu, and below <code>Unstaged</code> / <code>Staged</code> / <code>All</code> it lists the repository's branches. Picking one compares your working copy — uncommitted edits included — against that branch's tip, which is the view for \"what does this doc branch actually change?\".",
          "<strong>Hand a file to your editor with ⇧⌘E</strong> — Reader.md stays a reader, but editing is now one keystroke away. Pick your editor once (<strong>File → Set Default Editor…</strong>, or right-click any file → <strong>Always Open With</strong>) and from then on the menu reads <em>Open in Zed</em> and ⇧⌘E sends the open document straight there. Reader.md re-renders the moment you save, so your editor on one side and Reader.md on the other reads like a live preview.",
          "<strong>An appearance mode that follows macOS</strong> — the toolbar button now cycles Light → Dark → System, and in System mode Reader.md switches the moment macOS does, including on a schedule. New installs start in System, and the button's icon shows the mode you're <em>in</em> rather than the one you'd switch to.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "<strong>Folders inside a git repository respect <code>.gitignore</code></strong> — vendored and generated markdown stays out of the sidebar the way <code>node_modules</code> always has.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>A tooltip kept its old text when the button beneath it changed label</strong> — clicking the appearance button left the previous mode's tooltip on screen until you moved away and came back. It now re-renders in place.",
        ],
      },
    ],
  },
  {
    version: "1.14.1",
    date: "Jul 29, 2026",
    groups: [
      {
        tag: "FIXED",
        items: [
          "<strong>The close button covered a fullscreen diagram's controls</strong> — the floating × that closes the document sat on top of a fullscreen Mermaid diagram, overlapping its zoom controls in the top-right corner. It now steps aside while a diagram is fullscreen, and comes back when you leave.",
        ],
      },
    ],
  },
  {
    version: "1.14.0",
    date: "Jul 29, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>See what changed with ⇧⌘D</strong> — when a markdown file lives in a git repository, Reader.md can swap the rendered page for a side-by-side source diff. A word or two edited in a long paragraph is highlighted on its own, so a small change no longer paints the whole paragraph red and green. The button appears in the toolbar only for files inside a repository.",
          "<strong>Choose what you're comparing against</strong> — the diff header carries an <code>Unstaged | Staged | All</code> control, so you can read just your unstaged edits, just what you've staged, or everything since the last commit. Your choice is remembered.",
          "<strong>The outline becomes a hunk navigator</strong> — in diff mode the outline lists one row per changed block, labelled with the heading it sits under and its <code>+3 −2</code> counts — click one to jump straight to it.",
          "<strong>Changed files are marked in the sidebar</strong> — modified, added, untracked, and conflicted markdown files carry a small <code>M</code> / <code>A</code> / <code>?</code> / <code>U</code> badge.",
          "<strong>Zoom into Mermaid diagrams</strong> — diagrams no longer have to fit the column width to be readable. Hover one for zoom controls, pinch or ⌘-scroll to zoom, drag to pan, or open it fullscreen — it stays sharp at any size. ⌘E always exports the diagram at its fitted size.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "<strong>The sidebar keeps up with large folders</strong> — scrolling a document, typing in the filter, and opening Quick Open no longer redraw the whole file tree. With a few thousand markdown files across several folders, scrolling was visibly busy and each keystroke in the filter rebuilt every row.",
          "<strong>Filtering the sidebar shows a flat list of results</strong> — each hit is its filename over the folder it lives in (<code>notes › docs › api</code>), rather than the matching branches of the tree — so a filter over thousands of files stays instant, and <code>README.md</code> tells you which one it is.",
          "<strong>Folders are scanned in the background</strong> — adding a large folder, or opening the app with several, no longer freezes the window while the tree is read; the sidebar fills in as each folder finishes.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>Task list items showed a bullet and a checkbox</strong> — the checkbox now sits in the marker column on its own, matching GitHub.",
        ],
      },
    ],
  },
  {
    version: "1.13.0",
    date: "Jul 22, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Quick Open is now a command palette</strong> — start your query with <code>&gt;</code> to run an app command: toggle the theme, sidebar, or outline, cycle the content width, add a folder, open a file, add a remote, or export/copy-path for the open document — without hunting through menus.",
          "<strong>Jump to a heading with <code>#</code></strong> — start your query with <code>#</code> to fuzzy-search the headings in the document you're reading and jump straight to one.",
          "<strong>Keyboard hints and a result count</strong> — Quick Open gained a footer, and ⌘1–⌘9 opens one of the first nine results directly.",
        ],
      },
      {
        tag: "IMPROVED",
        items: [
          "<strong>Quick Open matches across the whole path, and shows why</strong> — ⌘P now fuzzy-matches your query against each file's full folder path, so <code>docsintro</code> finds <code>docs/intro.md</code> and typing a folder name scopes to the files under it. Results rank by match quality — a whole-filename hit beats the same letters scattered across a path — and the characters that matched are drawn bold in each row.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>Quick Open showed the previous query's files</strong> — changing your search updated the result count but could leave the earlier query's rows on screen.",
        ],
      },
    ],
  },
  {
    version: "1.12.0",
    date: "Jul 21, 2026",
    groups: [
      {
        tag: "IMPROVED",
        items: [
          "<strong>Quick Open searches every folder, and it's instant</strong> \u2014 \u2318P used to sort the whole index by folder name and cut the list short, so a large first folder hid every other folder and server you'd added. It now searches all of them, and builds its index once when it opens instead of re-scanning your folders on every keystroke.",
          "<strong>Quick Open matches like the sidebar</strong> \u2014 typing finds the same files the sidebar filter finds \u2014 any part of a filename, upper or lower case \u2014 instead of a looser fuzzy match that surfaced files you didn't mean.",
          "<strong>An empty Quick Open lists your recent files</strong> \u2014 the files you opened most recently, ten rows, the same cap search results use.",
        ],
      },
      {
        tag: "FIXED",
        items: [
          "<strong>Quick Open's arrow keys</strong> \u2014 up and down now move through the results you're actually looking at, and Return opens the highlighted one. They previously walked the list as it was before you started typing.",
        ],
      },
    ],
  },
  {
    version: "1.11.0",
    date: "Jul 15, 2026",
    groups: [
      {
        tag: "IMPROVED",
        items: [
          "<strong>Softer tooltips</strong> — hovering a button now shows a small rounded bubble that matches the app's chrome, in place of the yellow system tooltip.",
          "<strong>The Standard theme now matches GitHub</strong> — Standard adopts GitHub's exact colours for text, borders, and code, so it reads like github.com in both light and dark. The separate \"GitHub\" theme added in 1.10.0 is gone — Standard replaces it, and anyone who had GitHub selected is moved to Standard automatically.",
        ],
      },
    ],
  },
  {
    version: "1.10.0",
    date: "Jul 14, 2026",
    groups: [
      {
        tag: "ADDED",
        items: [
          "<strong>Highlights, notes, and comment threads</strong> — select text to highlight it in one of five colours, attach a note, or start a thread you can reply to and resolve. Anchored to the words, so an edit elsewhere leaves them in place; stored beside the file, never written into your markdown.",
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

// The version shown in the changelog header's "latest" pill. Derived from the
// list rather than kept alongside it — a hand-maintained copy went four
// releases stale. The list is ordered newest-first, which the page's timeline
// makes self-evident.
export const latestVersion = releasesLog[0].version;
