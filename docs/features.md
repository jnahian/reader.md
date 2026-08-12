---
title: Features
category: Reference
order: 20
summary: The complete inventory of what Reader.md does, and the keys that do it.
related: [reading, cli, install]
---

# Features

Everything Reader.md does, and the keys that do it. The app ships its own copy of
the shortcut list — **Help → Keyboard Shortcuts** (⌘/) — which is generated from
the same bindings.

This page is the inventory. Each feature area also has a page of its own under
`docs/features/`, covering it in depth with screenshots taken from the running
app.

## What it does

- **Open anything** — a single `.md` file (⌘O or double-click in Finder), whole folders, or a mix; set Reader.md as your default markdown handler
- **Multi-folder browser** — add any number of roots (multi-select, or drag folders onto the window); each is a collapsible section with hover-to-reveal actions, and roots reorder by drag
- **Remote (SSH) folders** — add a folder from a VPS: Reader.md `rsync`s it read-only into a local cache and shows it like any root. Auto-syncs on launch (quietly), manual re-sync, edit-the-connection-in-place, and a cloud badge with sync/error state. Reuses your `~/.ssh` config and keys — no credentials stored. Add via the **Add Remote** button in the sidebar footer
- **Cloned git repositories** — the same sheet takes a clone URL instead: Reader.md `git clone`s it read-only into a local cache and `pull --ff-only`s it on launch, with a branch badge in place of the cloud one. Uses your existing git credentials and never prompts — an unauthenticated repository fails with git's own error rather than hanging
- **Favorites** — pin files to a **FAVORITES** section between Recents and the folder tree: hover a file in the tree and click its star, right-click any file → **Add to Favorites**, press ⌘D for the open document, or use the ⌘P palette. Reorder by drag, unpin with the hover **×**; the list persists, a pinned file drops out of Recents (opening it never shuffles it away), and the bundled help docs and piped `reader -` documents can't be pinned
- **Context menus** — right-click any file, folder, root, or recent for Open / Always Open With / Reveal in Finder / Copy Path / Add to Favorites / Remove (and Edit Connection · Re-sync on remote roots)
- **Git-aware** — inside a repository, changed markdown gets a sidebar badge (`M` · `A` · `?` · `U`), ⇧⌘D shows the document as a side-by-side diff (word-level highlighting, hunks in the outline instead of headings), and the scope popover beside it compares against **Unstaged**, **Staged**, **All** (since the last commit), or any branch — "vs main" diffs your working copy, uncommitted edits included, against that branch's tip, with a filter field for repos with many branches. `.gitignore`d markdown stays out of the tree
- **Drag-and-drop** — drop a markdown file onto the content pane to open it
- **Quick open** — ⌘P fuzzy file switcher across all roots, with keyboard navigation
- **History & recents** — back/forward (⌘[ / ⌘]) plus a managed recent-files list in the sidebar, above Favorites (pinned files are listed only under Favorites)
- **File filter** — ⇧⌘F filters the tree live across all roots
- **In-page find** — ⌘F native find bar with match highlighting; step matches with the up/down chevrons beside the count, ⌘G / ⇧⌘G, or ⌘↩ / ⇧⌘↩
- **Outline** — collapsible right pane (⇧⌘B) with a sliding accent rail marker and scrollspy
- **Typography** — font size (⌘+ / ⌘− / ⌘0) and a narrow/wide/full-width canvas (⇧⌘\, wide by default), both persisted
- **Finder-style chrome** — capsule search field; native toolbar controls grouped into capsules by function; a "FOLDERS" section header with tinted icons and a full-width selection pill; and a window subtitle under the file name (word count and reading time, or the markdown file count when nothing is open), mirroring the macOS 26 Finder
- **Reading feedback** — accent progress bar under the toolbar; word count and reading time in the status bar
- **Code copy buttons**, **image click-to-zoom** lightbox, and hover **heading anchors**
- **Export to PDF** (⌘E) and **manual reload** (⌘R) — toolbar buttons on the right; the save dialog's Layout control picks page-by-page or one continuous page for that export, and the default it starts from lives in **Settings ▸ Editing & Export**
- **Hand off to an editor** (⇧⌘E) — Reader.md stays a reader; pick an editor once (**Settings ▸ Editing & Export**, **File → Set Default Editor…**, or right-click a file → **Always Open With**) and ⇧⌘E sends the open document there. The watcher re-renders on save, so an editor beside Reader.md reads as a live preview. Not offered for the bundled help docs, piped `reader -` documents, or read-only remote folders
- **Liquid Glass chrome** — on macOS 26 (Tahoe) the native toolbar, sidebar, outline, find bar, and quick-open palette all read as Liquid Glass; on macOS 13–15 they fall back to translucent `NSVisualEffectView` material. Collapsible + resizable sidebar (⌘B, width persisted); the title carries the document as a standard macOS proxy icon
- **Syntax highlighting, Mermaid, LaTeX math** — via the bundled JS engines
- **YAML frontmatter** — rendered as a clean key/value table at the top of the document
- **Appearance** — a light → dark → system cycle, applied to both native chrome and web content; System follows macOS live, including on a schedule
- **Live reload** — the open file re-renders (scroll preserved) and the tree refreshes on disk changes
- **Auto-update** — the packaged `.app` checks for and installs new releases via Sparkle
- **Settings** (⌘,) — appearance, reading theme, text size, canvas width, the external editor, and the default PDF export layout in one window. Mostly a second way into preferences the toolbar and menus already carry; the PDF layout default, clearing the external editor, and picking an appearance mode directly rather than cycling to it live only here
- **About panel** — version and credits from the standard macOS About window

## Keyboard shortcuts

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| ⌘O | Open file | ⌘P | Quick open |
| ⇧⌘A | Add folder | ⌥⌘A | Add remote folder |
| ⌘F | Find in page | ⇧⌘F | Filter files |
| ⌘G / ⇧⌘G (or ⌘↩ / ⇧⌘↩) | Find next / previous | ⌘[ / ⌘] | Back / forward |
| ⌘B | Toggle sidebar | ⇧⌘B | Toggle outline |
| ⇧⌘D | Toggle diff | ⇧⌘\ | Cycle canvas width |
| ⌘+ / ⌘− / ⌘0 | Text bigger / smaller / reset | ⇧⌘E | Open in editor |
| ⌘E | Export PDF | ⌘R | Reload |
| ⌘W | Close document | | |
| ⌘/ | Keyboard shortcuts | ⌘D | Add to / remove from Favorites |
| ⌘, | Settings | | |

Reader.md also has a command-line companion — see [the CLI reference](cli.md).
