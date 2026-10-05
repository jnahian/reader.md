---
title: Render LaTeX Math in Markdown on Mac
order: 21
summary: "Open markdown notes and see $…$ and $$…$$ LaTeX typeset by bundled KaTeX, offline, with live reload as you edit. A free, native Mac viewer for math notes."
related: [rendering, reading, exporting]
---

# Read markdown notes with LaTeX math on your Mac

Reader.md is a free markdown viewer for Mac that typesets the LaTeX math in
your notes instead of showing raw dollar signs. Reader.md renders inline and
display equations with KaTeX, bundled with the app, so lecture notes, papers in
progress, and technical docs read the way they were meant to, with no network
connection.

## How do I render LaTeX equations in a markdown file on a Mac?

Open the file in Reader.md and the math is typeset as you read. Open a single
file with Open File (⌘O), or add the folder of notes with Add Folder (⇧⌘A) so
every markdown file in it sits in the sidebar. There is nothing to enable:
math rendering is on for every document.

![Reader.md showing a markdown document with inline math and a centred display equation beside a Mermaid diagram](../assets/screenshots/rendering/03-diagram.png)

## Does markdown support LaTeX math?

Plain markdown has no math syntax; renderers add it, and each one picks its own
delimiters. That is why the same file can show typeset equations in one preview
and raw `$x^2$` in another. Reader.md reads the delimiters most math notes
already use:

| You write | Reader.md renders |
|---|---|
| `$…$` | inline math, in the middle of a sentence |
| `\(…\)` | inline math |
| `$$…$$` | a centred display block |
| `\[…\]` on its own line | a centred display block |

Mid-sentence, `\[1\]` stays a literal `[1]`, so bracketed references are not
mistaken for equations. See
[Diagrams and math](../features/rendering.md#diagrams-and-math).

## Why does my inline `$` math show as raw text?

Many markdown previews only render display `$$` math, or none at all, so inline
`$…$` comes through as plain text. Reader.md renders single-dollar inline math.
Reader.md also keeps the LaTeX intact before the markdown parser can touch it:

- `\\` line breaks inside matrices, `aligned`, and `cases` are preserved, so
  multi-row environments stay multi-row.
- `*` and `_` inside math stay as LaTeX instead of turning into italics.
- Math inside a code span or a fenced code block stays literal, so you can
  document the syntax itself.

## Will prices like "$5 and $10" turn into math?

No. A `$` only closes inline math when there is no space just inside it and no
digit right after it. "Costs $5 and $10" reads as two prices in Reader.md,
while `$x$` still renders as math.

## Does it need the internet?

No. KaTeX and its fonts ship inside Reader.md, so equations render the same on
a plane as at a desk. Markdown, diagrams, math, and syntax highlighting all
come from bundled assets; the only outbound request Reader.md makes is its
update check.

## What LaTeX does Reader.md support?

Reader.md supports the math KaTeX supports: a large subset of LaTeX math
commands, not full LaTeX. Reader.md renders equations inside markdown only; it
does not compile `.tex` documents, load packages with `\usepackage`, or draw
TikZ. KaTeX keeps its own
[list of supported functions](https://katex.org/docs/supported.html).

## Write in your editor, preview math in Reader.md

Keep your editor beside Reader.md and every save re-renders the document where
it stands, with your scroll position kept, so a long derivation does not jump
back to the top. Open in Editor (⇧⌘E) hands the open document to your chosen
editor, which makes Vim, VS Code, or any other editor plus Reader.md a live math
preview. See [Live reload](../features/rendering.md#live-reload), and for a
terminal editor setup,
[A markdown preview for Neovim, Vim, Helix, and Zed on Mac](markdown-preview-neovim-mac.md).

![A document in Reader.md re-rendering as the file changes on disk](../assets/screenshots/rendering/04-reload.mp4)

## Reading long math notes

A semester of lecture notes gets long. Toggle Outline (⇧⌘B) lists the headings
of the open document in a side pane, marks the section you are in, and jumps to
any heading you click. Find in Page (⌘F) searches the document text. See
[The outline](../features/reading.md#the-outline).

## Math and Mermaid in the same document

Reader.md renders both in one page: a fenced code block tagged `mermaid` is
drawn as a diagram, and the equations around it are typeset. For diagram
controls such as zoom and fullscreen, see
[View Mermaid diagrams on your Mac, offline](mermaid-diagram-viewer-mac.md).

## Can I export markdown with equations to PDF?

Yes. Export as PDF (⌘E) saves the document as you are reading it, typeset math
included, in the same theme and text size. See
[Convert markdown to PDF on your Mac, then share it](markdown-to-pdf-mac.md).

## Get Reader.md

Reader.md is a free, open-source (MIT) markdown viewer with built-in LaTeX math
for macOS 13 or later on Apple silicon. Install it with Homebrew or the DMG —
see [Install](../install.md).
