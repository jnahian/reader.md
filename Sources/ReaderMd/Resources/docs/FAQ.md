# Reader.md — FAQ

A native macOS markdown viewer. Everything renders locally; the only network
access is the auto-update check.

## Opening files

**How do I open a folder?**
Drag a folder onto the window, or **File → Add Folder…**. Reader.md scans it
recursively for markdown files (skipping `node_modules`, `.git`, and friends)
and watches it for changes — edits re-render live. In a git repository it also
skips anything your `.gitignore` covers, so vendored and generated markdown
stays out of the sidebar.

**How do I open a single file?**
**File → Open File…** (⌘O), or drag a `.md` file onto the window. Single files
open without adding a folder to the sidebar.

**Can I set Reader.md as my default markdown app?**
Yes — in Finder, right-click a `.md` file → **Get Info** → **Open with** →
choose Reader.md → **Change All…**.

**Can I edit files in Reader.md?**
No — Reader.md is a reader, and it hands editing to your editor. Choose one in
**Settings ▸ Editing & Export** (⌘,), with **File → Set Default Editor…**, or by
right-clicking any file → **Always Open With**, then
⇧⌘E sends the open document straight there. The folder watcher re-renders on
save, so your editor on one side and Reader.md on the other behaves like a live
preview. ⇧⌘E stays greyed out until you've picked an editor, and for documents
there's nothing to edit — the help pages, `reader -` input, and remote folders.

## Reading

**How do I jump between files quickly?**
**Quick Open** (⌘P) — fuzzy-search every file across all your folders (it matches
the folder path too). Start the query with `>` to run a command, or `#` to jump
to a heading in the document you're reading.

**Can I pin the files I keep coming back to?**
Yes — **Favorites**. Click the star that appears when you hover a file in the
sidebar, right-click any file → **Add to Favorites**, or press ⌘D for the open
document. Pinned files sit in a **FAVORITES** section in the sidebar, below
Recents and above your folders, and stay there until you unpin them — drag to
reorder, and the hover **×** (or the context menu) removes one. Recents churns as you read;
Favorites don't — a pinned file drops out of Recents and stays where you put it.
The bundled help pages and `reader -` documents can't be pinned.

**Where's the document outline?**
Toggle it with ⇧⌘B. It tracks your scroll position and clicking a heading jumps
to it.

**Does it support diagrams and math?**
Yes. Mermaid fenced code blocks render as diagrams, and LaTeX (`$…$` /
`$$…$$`) renders via KaTeX. Syntax highlighting is built in.

**Can I change the theme or text size?**
Light/dark follows the toggle in the topbar, which also picks a reading theme —
Standard, Editorial, or Terminal. Text size is ⌘+ / ⌘- / ⌘0, and
**View → Canvas Width** picks Narrow, Wide (the default), or Full Width (⇧⌘\ cycles them). Full Width fills the window, so wide tables stop scrolling sideways.

All four also live in **Settings** (⌘,), if you'd rather set them in one place.

In the Standard theme, links and heading anchors use the accent color you picked
in System Settings, and follow it when you change it. Editorial and Terminal keep
their own accents.

## Annotations

**How do I highlight or comment on text?**
Select text and use the markup popover to highlight or attach a note. Comment
threads can be resolved. Annotations are stored locally in
`~/Library/Application Support/Reader.md/` keyed by file — they survive edits
to the file, but are lost if the file is renamed or moved.

## Exporting & searching

**How do I export to PDF?**
**File → Export as PDF…** (⌘E) renders the current document to PDF. A **Layout**
control in the save dialog picks **Page by Page** — real pages at your system
paper size — or **Continuous**, one long page. That choice applies to the one
export; the default it starts from is **Settings ▸ Editing & Export**.
Paginated pages take the reading theme's paper color, so dark
documents export as dark pages, and long code lines wrap to the page instead of
being cut off at the edge. Links stay clickable in either layout.

**How do I search within a document?**
Find in Page (⌘F) highlights every match and shows a live "N of M" count; step
through matches with the ⌃/⌄ chevrons beside the count, ⌘G / ⇧⌘G, or ⌘↩ / ⇧⌘↩.
To filter the file list in the sidebar, use ⇧⌘F.

## Git

**Does it know about git?**
Yes, for any folder inside a repository. Changed files get a badge in the
sidebar (`M`, `A`, `?`, `U`), and ⇧⌘D shows the document as a side-by-side diff
with the outline listing hunks instead of headings.

**What can I diff against?**
The button beside the diff toggle names what you're comparing against and opens
a popover to change it: **Unstaged**, **Staged**, **All** (since the last
commit), or any branch in the repo — "vs main" compares your working copy,
uncommitted edits included, against that branch's tip. In a repo with many
branches the popover has a filter field, so you can type part of a branch name
instead of scrolling for it.

## Remote folders

**Can I read markdown on a remote server?**
Yes — add a remote (SSH) folder. Reader.md syncs it read-only to a local cache
via rsync, so browsing stays fast and offline-friendly.

**Can I read a git repository I haven't checked out?**
Yes — choose **Git** in the Add Remote sheet and paste a clone URL. Reader.md
clones it read-only into a local cache and fast-forwards it on launch, using
your existing git credentials. It never prompts, so a repository you can't
authenticate to fails with git's own error instead of hanging.

## Updates

**How do I update?**
Reader.md checks for updates automatically. You can also trigger it from
**Reader.md → Check for Updates…**, which is greyed out only while a check is
already running. Updates are delivered to Apple-silicon Macs.

**I dismissed the update prompt — how do I get it back?**
**Remind Later** only defers an offer, so the next check — automatic or from
**Check for Updates…** — brings it back. **Skip This Version** is the one that
passes on a release for good; a later release is still offered.

## Something's wrong

Found a bug or have a request? **Help → Report an Issue…** opens the GitHub
issue tracker.
