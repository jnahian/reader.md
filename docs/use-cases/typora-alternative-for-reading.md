---
title: A Free Typora Alternative for Reading Markdown
order: 17
summary: "Typora is made for writing. If you mostly read markdown, Reader.md is a free, open-source Mac reader with a folder sidebar, outline, Mermaid, math, live reload."
related: [library, rendering, exporting, install]
---

# A free Typora alternative for when you only read markdown

Reader.md is a free, open-source markdown reader for Mac. If you open Typora
mostly to read markdown rather than write it, Reader.md covers that reading
half: folders in a sidebar, an outline, Mermaid diagrams, LaTeX math, and
live reload, with no license to buy.

## Who this is for

Reader.md suits people who read more markdown than they write: READMEs, design
docs, notes, runbooks, and the documents a coding agent produces. Reader.md
does not edit. If Typora is where you write, keep it; Reader.md replaces it
only for the reading.

The usual sign is a day spent opening files to look at them rather than
change them: checking a README before a push, skimming a folder of meeting
notes, reading a long spec. Reader.md is built for that job. It opens whole
folders at once, remembers recent files and favorites, and keeps every
document in the same window, with back and forward between them like a
browser.

## Is Typora free?

Typora is a paid app. Its own site, typora.io, lists it at $14.99 (without
tax) after a 15-day free trial. Typora describes itself as "a minimal markdown editor and
reader", and runs on macOS, Windows, and Linux.

Reader.md is free and MIT-licensed, with the source on GitHub. It runs only on
Macs with Apple silicon, on macOS 13 or later.

## Typora vs Reader.md

The two apps overlap on rendering and differ on editing. Typora facts below
come from typora.io.

| | Typora | Reader.md |
|---|---|---|
| Price | $14.99 after a 15-day trial | Free, MIT licence |
| Platforms | macOS, Windows, Linux | macOS 13+, Apple silicon |
| Edits markdown | Yes, editor-first | No, read-only |
| Mermaid and math | Yes | Yes, bundled, offline |
| Outline | Outline panel | Outline pane (⇧⌘B) |
| Export | PDF, DOCX, EPUB, LaTeX, and more | PDF only |
| Themes | Configurable by CSS | Three reading themes, Light / Dark / System |

## Read-only by design

Reader.md never writes to your documents. It has no editing mode to switch
out of, so reading a file cannot change it by accident. Highlights and notes
you add are stored on your Mac under
`~/Library/Application Support/Reader.md/`, keyed by the file's path, so the markdown
itself stays untouched.

## A folder sidebar, not one file at a time

Reader.md keeps every folder you add in one sidebar. **Add Folder** (⇧⌘A)
turns any folder into a root, and only markdown files appear in the tree;
`node_modules` and `.git` are skipped.

![Reader.md's sidebar with two folders, Recents, and Favorites, beside a rendered document](../assets/screenshots/library/01-sidebar.png)

Two ways find a file once the folders are in:

- **Filter Files (⇧⌘F)** searches file names across every root at once.
- **Quick Open (⌘P)** is a fuzzy switcher that matches folder paths as well as
  names.

See [Finding your files](../features/library.md#folders-in-the-sidebar) and
[Every markdown folder on your Mac in one library](find-markdown-files-across-folders.md).

## What renders

Reader.md renders GitHub-flavoured markdown with tables, footnotes, and task
lists, plus the three things a plain renderer drops: Mermaid diagrams, LaTeX
math through KaTeX, and syntax-highlighted code. Every engine is bundled with
the app, so nothing renders over the network. YAML frontmatter shows as a
key/value table above the document.

![A Mermaid diagram and a LaTeX formula rendered in Reader.md's dark appearance](../assets/screenshots/rendering-showcase/01-rendering.png)

See [Diagrams and math](../features/rendering.md#diagrams-and-math) and
[View Mermaid diagrams on your Mac, offline](mermaid-diagram-viewer-mac.md).

## Keep your editor, preview in Reader.md

Reader.md pairs with whatever editor you already use. Pick one once in
Settings, and Open in Editor (⇧⌘E) hands it the open document. Save in the
editor and Reader.md re-renders the file where it stands, scroll position
kept, which makes the two windows a live preview.

![Reader.md re-rendering an open document as the file changes on disk](../assets/screenshots/rendering/04-reload.mp4)

See [Live reload](../features/rendering.md#live-reload) and
[Hand the document to an editor](../features/exporting.md#hand-the-document-to-an-editor).

## What is a good markdown reader for Mac?

For reading rather than writing, Reader.md is a free, native markdown reader
for Mac: folders in a sidebar, an outline, Mermaid and math, live reload, and
PDF export (⌘E). It also has Light, Dark, and System appearance, three reading
themes, and focus mode (⌥⌘F). From a terminal, `reader README.md` opens a file
and `reader .` adds the current folder; see the [command line](../cli.md).

## Get Reader.md

Reader.md is free and MIT-licensed, for macOS 13 or later on Apple silicon.
See [Install](../install.md) for Homebrew and the direct download.
