---
title: Render Markdown from the Terminal on Mac
order: 9
summary: "Pipe pandoc or an LLM CLI into reader - and the markdown opens rendered in a native Mac window, with Mermaid diagrams, math, find in page, and PDF export."
related: [cli, rendering, exporting, install]
---

# Render markdown from the terminal in a Mac window

Reader.md is a free markdown viewer for Mac with a `reader` command, so any
markdown a terminal command produces can open as a rendered document in a
native window. Pipe output into `reader -`, or pass a file or folder, and
Reader.md draws it with headings, tables, code highlighting, Mermaid diagrams,
and LaTeX math.

## How do I preview markdown output from a command?

Pipe the command into `reader -`. Reader.md reads standard input, writes it to
a temporary file, and opens that file as a rendered document in its window.

```bash
pandoc notes.rst -t gfm | reader -
git diff | reader -
```

Reader.md treats whatever arrives as markdown, so the pipe works best with
commands that emit markdown. `reader -` waits for the command to finish
(end of input) and then opens the document once. Reader.md does not stream
output as it arrives, and a second pipe opens a second document. See
[Piping](../cli.md#piping).

A bare `reader -` typed at a terminal, with nothing piped in, says so and
exits instead of waiting for input.

## Render LLM CLI output as markdown

Command-line LLM tools answer in markdown: headings, lists, tables, fenced
code. Piping that answer into `reader -` turns it into a readable page instead
of raw asterisks and pipes in the scrollback: end the LLM command with
`| reader -`.

The same pipe works for any tool that writes markdown to standard output,
local models included. Because Reader.md opens the document after the command
exits, a long answer appears complete rather than drawing in line by line.

For documents a coding agent writes to disk, such as plans and specs, see
[Review what your coding agent writes](review-ai-agent-docs.md).

## Convert other formats, then read

Pandoc converts other document formats to markdown, and Reader.md renders
the result. `pandoc notes.rst -t gfm | reader -` is the
documented pattern: pandoc writes GitHub-flavoured markdown, Reader.md
displays it.

## Why render in a window instead of the terminal?

Reader.md renders piped markdown in a native window so Mermaid diagrams and
LaTeX math are drawn, not left as source. In-terminal renderers such as Glow
style markdown as terminal text; Reader.md is the window counterpart for
output that has more than text in it.

What a piped document gets in Reader.md:

- **Mermaid diagrams** drawn from `mermaid` fences, with zoom and fullscreen
- **LaTeX math**, inline and as display blocks
- **Syntax-highlighted code** with a Copy button on each block
- **Tables and frontmatter** rendered as tables
- **Offline rendering** — everything needed is bundled with the app

See [Diagrams and math](../features/rendering.md#diagrams-and-math).

![A Mermaid diagram and LaTeX math rendered in Reader.md](../assets/screenshots/rendering/03-diagram.png)

## What happens to piped markdown documents?

Piped documents behave like any other document for reading, with a few limits
because they are temporary files.

- **Can:** scroll, search with Find in Page (⌘F), and Export as PDF (⌘E).
- **Cannot:** be added to Favorites or handed to an editor (⇧⌘E).
- **Lifetime:** Reader.md cleans piped documents up a day later.

Find in Page counts and highlights every match, and ⌘G and ⇧⌘G step through
them. See [Finding text in a document](../features/reading.md#finding-text-in-a-document).

![In-page find in Reader.md, with the match count and step controls](../assets/screenshots/reading/03-find.png)

## How do I export terminal markdown output to PDF?

Pipe the output into `reader -`, then choose Export as PDF (⌘E). The save
dialog offers **Page by Page** or **Continuous** layout, and the PDF keeps
the reading theme and text size you see on screen. See
[Export as PDF](../features/exporting.md#export-as-pdf), or
[Convert markdown to PDF on your Mac, then share it](markdown-to-pdf-mac.md)
for the full workflow.

## Open files and folders from the command line too

The `reader` command opens files on disk as well as piped text:

```bash
reader README.md      # open one markdown file
reader .              # add the current folder to the sidebar
```

A file opened this way lives on disk, so Reader.md re-renders it whenever it
changes and keeps your scroll position. Every command is listed in the
[command line reference](../cli.md).

## How do I install the reader command?

Homebrew puts `reader` on your PATH automatically. After a DMG install,
choose **File → Install `reader` Command Line Tool…**, launching Reader.md
once first so macOS clears quarantine. Each `reader` command hands its work to
the Reader.md app, launching it if it is not already running.

## Get Reader.md

Reader.md is a free, open-source (MIT) markdown viewer for macOS 13 or later
on Apple silicon. Install it with Homebrew or the DMG — see
[Install](../install.md).
