---
title: Features
category: Reference
order: 20
summary: Everything Reader.md does, in one list, with the page that covers each in depth.
related: [reading, cli, install]
---

# Features

One line per feature, and a link to the page that covers it properly. If you are
looking for *how* something works, follow the link; if you are looking for
*whether* it exists, this page is the list.

The shortcut tables at the end are the same list the app ships at
**Help → Keyboard Shortcuts** (⌘/), which is generated from the key bindings
themselves.

## Finding your files

See [Finding your files](features/library.md).

- **Any number of folders** — add roots by ⇧⌘A, by dropping folders on the window, or with `reader <folder>`; each is a collapsible section, and they reorder by drag
- **Recents and Favorites** — a managed recent-files list, and a pinned section above it (⌘D, the hover star, or right-click → **Add to Favorites**); pinning moves a file out of Recents, and the bundled help docs and piped documents can't be pinned
- **File filter** (⇧⌘F) — filters every root at once by file name, each result labelled with the folder it came from
- **Quick Open** (⌘P) — fuzzy switcher over every file in every root, matching the folder path as well as the name; `>` runs a command, `#` jumps to a heading, ⌘1–⌘9 open a result directly

## Opening and moving between files

See [Opening and moving between files](features/navigating.md).

- **Open anything** — a single file (⌘O, Finder, or drag onto the window), whole folders, or a mix; Reader.md registers as a markdown viewer, so it can be the Finder default
- **Back and forward** (⌘[ / ⌘]) — a history stack across every document you open, links between markdown files included
- **Context menus** — right-click any file, folder, root, or recent for Open / Always Open With / Reveal in Finder / Copy Path / Add to Favorites / Remove
- **Sidebar** (⌘B) — collapsible and resizable, width remembered

## Reading a document

See [Reading a document](features/reading.md).

- **Outline** (⇧⌘B) — the heading structure in a right-hand pane, tracking your position as you scroll
- **Find in page** (⌘F) — match count and highlighting, stepped with the chevrons, ⌘G / ⇧⌘G, or ⌘↩ / ⇧⌘↩
- **Text size** (⌘+ / ⌘− / ⌘0) and **canvas width** (⇧⌘\\, narrow / wide / full) — both persisted
- **Reading feedback** — a progress bar under the toolbar, with the word count and reading time under the file name
- **Resume where you stopped** — a long document reopens at the place you left it
- **Focus mode** (⌥⌘F) — one toggle hides the chrome, goes fullscreen, and dims everything outside the section you're reading

## How a document is rendered

See [How a document is rendered](features/rendering.md).

- **GitHub-flavoured markdown**, with tables, footnotes, and task lists
- **Syntax highlighting, Mermaid diagrams, and LaTeX math** — from engines bundled with the app, so nothing renders over the network
- **Diagram controls** — zoom, reset, fullscreen, pinch or ⌘-scroll, and drag to pan
- **YAML frontmatter** — rendered as a key/value table above the document
- **Code copy buttons**, **image click-to-zoom**, and hover **heading anchors**
- **Live reload** (and ⌘R) — the open file re-renders as it changes on disk, scroll preserved, and the tree refreshes with it

## Highlights and notes

See [Highlights and notes](features/annotations.md).

- **Highlight** a selection in one of five colours
- **Attach a note**, or a whole comment thread with replies and **Resolve** — with a resolved count in the toolbar that doubles as a show/hide switch
- **Anchored to the words**, not to a position, so an edit elsewhere leaves a mark where it was; one whose text disappears is flagged as orphaned rather than dropped
- **Never written into your markdown** — annotations live beside the file, keyed by its path

## Working in a git repository

See [Working in a git repository](features/git.md).

- **Change badges** in the sidebar — `M` · `A` · `?` · `U`
- **Side-by-side diff** (⇧⌘D) with word-level highlighting, and hunks in the outline instead of headings
- **Diff scope** — **Unstaged**, **Staged**, **All**, or any branch in the repository
- **`.gitignore` is respected** — ignored markdown never enters the tree

## Remote and cloned folders

See [Remote and cloned folders](features/remote.md).

- **A folder over SSH** (⌥⌘A) — `rsync`ed read-only into a local cache, using your `~/.ssh` config and keys, with no credentials stored
- **A cloned git repository** — the same sheet takes a clone URL, cloned read-only and `pull --ff-only`ed on launch, using your existing git credentials and never prompting
- **Sync state in the sidebar** — a cloud or branch badge, a spinner while syncing, and an amber badge carrying the error if a sync fails
- **Edit connection**, **Re-sync**, and **Remove** on the root itself

## Exporting and editing

See [Exporting and editing](features/exporting.md).

- **Export as PDF** (⌘E) — page-by-page or one continuous page, chosen per export, defaulting to the setting
- **Hand off to an editor** (⇧⌘E) — pick one once, and every save comes straight back through the watcher
- **Reader.md never writes to your documents**

## Settings

See [Settings](features/settings.md).

- **Appearance** — light, dark, or system, applied to chrome and content alike; system follows macOS as it changes
- **Reading themes** — Standard, Editorial, or Terminal, restyling the document without touching the window
- **Text size, canvas width, external editor, and the default PDF layout** in one window (⌘,)

## Chrome, and the rest

No page of its own — this is the whole of it.

- **Liquid Glass** — on macOS 26 the toolbar, sidebar, outline, find bar, and Quick Open all read as Liquid Glass; on macOS 13–15 they fall back to translucent `NSVisualEffectView` material
- **Finder-style chrome** — a capsule search field, toolbar controls grouped into capsules by function, a **FOLDERS** header with tinted icons and a full-width selection pill, and the document carried in the title as a standard proxy icon
- **Auto-update** — the packaged app checks for and installs new releases through Sparkle, and opens the changelog once afterwards. See [Install](install.md)
- **About panel** — version and credits in the standard macOS window, with
  clickable **Website**, **Docs**, and **Report an Issue** links; the Help menu
  carries the same destinations
- **A command-line companion** — see [the CLI reference](cli.md)

## Keyboard shortcuts

The same list the app shows at **Help → Keyboard Shortcuts** (⌘/). A test keeps
the two from drifting: every shortcut in the app's copy has to appear here.

### Files

| Shortcut | Action |
|---|---|
| ⌘O | Open File… |
| ⇧⌘A | Add Folder… |
| ⌥⌘A | Add Remote Folder… |
| ⌘P | Quick Open (files, `>` commands, `#` headings) |
| ⌘D | Add to / Remove from Favorites (the open document) |
| ⇧⌘E | Open in Editor |
| ⌘E | Export as PDF… |
| ⌘R | Reload |
| ⌘W | Close the open document |

### Navigation

| Shortcut | Action |
|---|---|
| ⌘[ | Back |
| ⌘] | Forward |
| ⌘B | Toggle Sidebar |
| ⇧⌘B | Toggle Outline |

### Find

| Shortcut | Action |
|---|---|
| ⌘F | Find in Page |
| ⌘G or ⌘↩ | Find Next |
| ⇧⌘G or ⇧⌘↩ | Find Previous |
| ⎋ | Clear the find field |
| ⇧⌘F | Filter Files (sidebar) |

### Quick Open

| Shortcut | Action |
|---|---|
| ↑ ↓ | Move through results |
| ⏎ | Open / run the selected result |
| ⌘1–⌘9 | Open the first nine results directly |
| ⎋ | Dismiss |

### View

| Shortcut | Action |
|---|---|
| ⌘+ | Increase Text |
| ⌘- | Decrease Text |
| ⌘0 | Actual Size |
| ⇧⌘\\ | Cycle Canvas Width (Narrow / Wide / Full) |
| ⇧⌘D | Toggle Diff (in a git repository) |
| ⌥⌘F | Focus Mode (hides the chrome, dims other sections) |

### Settings and help

| Shortcut | Action |
|---|---|
| ⌘, | Open Settings |
| ⌘/ | Keyboard Shortcuts |
