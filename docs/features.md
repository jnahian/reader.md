# Features

Everything Reader.md does, and the keys that do it. The app ships its own copy of
the shortcut list — **Help → Keyboard Shortcuts** (⌘/) — which is generated from
the same bindings.

## Features

- **Open anything** — a single `.md` file (⌘O or double-click in Finder), whole folders, or a mix; set Reader.md as your default markdown handler
- **Multi-folder browser** — add any number of roots (multi-select, or drag folders onto the window); each is a collapsible section with hover-to-reveal actions, and roots reorder by drag
- **Remote (SSH) folders** — add a folder from a VPS: Reader.md `rsync`s it read-only into a local cache and shows it like any root. Auto-syncs on launch (quietly), manual re-sync, edit-the-connection-in-place, and a cloud badge with sync/error state. Reuses your `~/.ssh` config and keys — no credentials stored. Add via the **Add Remote** button in the sidebar footer
- **Cloned git repositories** — the same sheet takes a clone URL instead: Reader.md `git clone`s it read-only into a local cache and `pull --ff-only`s it on launch, with a branch badge in place of the cloud one. Uses your existing git credentials and never prompts — an unauthenticated repository fails with git's own error rather than hanging
- **Git-aware** — inside a repository, changed markdown gets a sidebar badge (`M` · `A` · `?` · `U`), ⇧⌘D shows the document as a side-by-side diff (word-level highlighting, hunks in the outline instead of headings), and the scope menu compares against **Unstaged**, **Staged**, **All** (since the last commit), or any branch — "vs main" diffs your working copy, uncommitted edits included, against that branch's tip. `.gitignore`d markdown stays out of the tree
- **Favorites** — pin files to a **FAVORITES** section between Recents and the folder tree: hover a file in the tree and click its star, right-click any file → **Add to Favorites**, press ⌘D for the open document, or use the ⌘P palette. Reorder by drag, unpin with the hover **×**; the list persists, and the bundled help docs and piped `reader -` documents can't be pinned
- **Context menus** — right-click any file, folder, root, or recent for Open / Always Open With / Reveal in Finder / Copy Path / Add to Favorites / Remove (and Edit Connection · Re-sync on remote roots)
- **Drag-and-drop** — drop a markdown file onto the content pane to open it
- **Quick open** — ⌘P fuzzy file switcher across all roots, with keyboard navigation
- **History & recents** — back/forward (⌘[ / ⌘]) plus a managed recent-files list in the empty state, with the pinned Favorites section under it
- **File filter** — ⇧⌘F filters the tree live across all roots
- **In-page find** — ⌘F native find bar with match highlighting (⌘G / ⇧⌘G for next/prev)
- **Outline** — collapsible right pane (⇧⌘B) with a sliding accent rail marker and scrollspy
- **Typography** — font size (⌘+ / ⌘− / ⌘0) and a narrow/wide/full-width reading column (⇧⌘\), both persisted
- **Finder-style chrome** — capsule search field; native toolbar controls grouped into capsules by function; a "FOLDERS" section header with tinted icons and a full-width selection pill; and a bottom status bar (markdown file count, or word count / reading-time for the open file), mirroring the macOS 26 Finder
- **Reading feedback** — accent progress bar under the toolbar; word count and reading time in the status bar
- **Code copy buttons**, **image click-to-zoom** lightbox, and hover **heading anchors**
- **Export to PDF** (⌘E) and **manual reload** (⌘R) — toolbar buttons on the right, plus the web view's native PDF renderer
- **Hand off to an editor** (⇧⌘E) — Reader.md stays a reader; pick an editor once (**File → Set Default Editor…**, or right-click a file → **Always Open With**) and ⇧⌘E sends the open document there. The watcher re-renders on save, so an editor beside Reader.md reads as a live preview. Not offered for the bundled help docs, piped `reader -` documents, or read-only remote folders
- **Liquid Glass chrome** — on macOS 26 (Tahoe) the native toolbar, sidebar, outline, find bar, and quick-open palette all read as Liquid Glass; on macOS 13–15 they fall back to translucent `NSVisualEffectView` material. Collapsible + resizable sidebar (⌘B, width persisted); the title's proxy icon reveals the file in Finder
- **Syntax highlighting, Mermaid, LaTeX math** — via the bundled JS engines
- **YAML frontmatter** — rendered as a clean key/value table at the top of the document
- **Appearance** — a light → dark → system cycle, applied to both native chrome and web content; System follows macOS live, including on a schedule
- **Live reload** — the open file re-renders (scroll preserved) and the tree refreshes on disk changes
- **Auto-update** — the packaged `.app` checks for and installs new releases via Sparkle
- **About panel** — version and credits from the standard macOS About window

## Keyboard shortcuts

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| ⌘O | Open file | ⌘P | Quick open |
| ⇧⌘A | Add folder | ⌥⌘A | Add remote folder |
| ⌘F | Find in page | ⇧⌘F | Filter files |
| ⌘G / ⇧⌘G | Find next / previous | ⌘[ / ⌘] | Back / forward |
| ⌘B | Toggle sidebar | ⇧⌘B | Toggle outline |
| ⇧⌘D | Toggle diff | ⇧⌘\ | Cycle column width |
| ⌘+ / ⌘− / ⌘0 | Text bigger / smaller / reset | ⇧⌘E | Open in editor |
| ⌘E | Export PDF | ⌘R | Reload |
| ⌘/ | Keyboard shortcuts | ⌘D | Add to / remove from Favorites |

Reader.md also has a command-line companion — see [the CLI reference](cli.md).
