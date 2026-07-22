# Reader.md — FAQ

A native macOS markdown viewer. Everything renders locally; the only network
access is the auto-update check.

## Opening files

**How do I open a folder?**
Drag a folder onto the window, or **File → Add Folder…**. Reader.md scans it
recursively for markdown files (skipping `node_modules`, `.git`, and friends)
and watches it for changes — edits re-render live.

**How do I open a single file?**
**File → Open File…** (⌘O), or drag a `.md` file onto the window. Single files
open without adding a folder to the sidebar.

**Can I set Reader.md as my default markdown app?**
Yes — in Finder, right-click a `.md` file → **Get Info** → **Open with** →
choose Reader.md → **Change All…**.

## Reading

**How do I jump between files quickly?**
**Quick Open** (⌘P) — fuzzy-search every file across all your folders (it matches
the folder path too). Start the query with `>` to run a command, or `#` to jump
to a heading in the document you're reading.

**Where's the document outline?**
Toggle it with ⇧⌘B. It tracks your scroll position and clicking a heading jumps
to it.

**Does it support diagrams and math?**
Yes. Mermaid fenced code blocks render as diagrams, and LaTeX (`$…$` /
`$$…$$`) renders via KaTeX. Syntax highlighting is built in.

**Can I change the theme or text size?**
Light/dark follows the toggle in the topbar, which also picks a reading theme —
Standard, Editorial, or Terminal. Text size is ⌘+ / ⌘- / ⌘0, and
**View → Column Width** picks Narrow, Wide, or Full Width (⇧⌘\ cycles them). Full Width fills the window, so wide tables stop scrolling sideways.

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
**File → Export as PDF…** (⌘E) renders the current document to PDF.

**How do I search within a document?**
Find in Page (⌘F) highlights every match and shows a live "N of M" count; step
through matches with ⌘G / ⇧⌘G. To filter the file list in the sidebar, use ⇧⌘F.

## Remote folders

**Can I read markdown on a remote server?**
Yes — add a remote (SSH) folder. Reader.md syncs it read-only to a local cache
via rsync, so browsing stays fast and offline-friendly.

## Updates

**How do I update?**
Reader.md checks for updates automatically. You can also trigger it from
**Reader.md → Check for Updates…**. Updates are delivered to Apple-silicon Macs.

## Something's wrong

Found a bug or have a request? **Help → Report an Issue…** opens the GitHub
issue tracker.
