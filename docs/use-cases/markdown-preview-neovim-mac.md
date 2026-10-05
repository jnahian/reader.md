---
title: Markdown Preview for Neovim and Vim on Mac
order: 15
summary: "Keep Neovim, Vim, Helix, Zed, or Sublime for writing. Reader.md renders the file beside it on Mac and re-renders on every save, with your scroll position kept."
related: [cli, rendering, exporting, library]
---

# A markdown preview for Neovim, Vim, Helix, and Zed on Mac

Reader.md is a free markdown viewer for Mac that works as a preview window for
whichever editor you write in. Reader.md watches your project folder on disk,
so every save from Neovim, Vim, Helix, Zed, or Sublime Text re-renders the
page in a native window beside the editor, with no plugin to install.

## How do I preview markdown in Neovim?

Add your project folder to Reader.md once, then open the file you are editing
with `:!reader %`. Every `:w` after that re-renders the page in Reader.md,
where it stands, with your scroll position kept.

The same works from any shell:

```
reader .                 add the current directory to the sidebar
reader notes.md          open a markdown file
```

`reader` comes with the Homebrew install; from the DMG, use **File → Install
`reader` Command Line Tool…** once. See the [command line](../cli.md) reference.

## Can I preview markdown in Vim on a Mac?

Yes. Vim, Neovim, and any other editor that saves files to disk pair with
Reader.md the same way, because Reader.md watches the folder rather than
talking to the editor. Put the Vim window and Reader.md side by side, write in
one, and read in the other.

## Does it need a Vim plugin?

No. Reader.md needs no plugin, no local server, and no browser tab. The
`reader` command hands the file to the app, and the folder watcher does the
rest. Your editor configuration stays as it is.

That is the main difference from a plugin such as markdown-preview.nvim, which
previews in your web browser and keeps the browser's scroll position in step
with your cursor. Reader.md renders in its own window and does not follow the
cursor: it keeps its own scroll position across reloads, and you scroll it
yourself.

## How it stays in sync

Reader.md re-renders on save, not as you type. When the file changes on disk,
the open document re-renders where it stands, and the sidebar refreshes if
files were added or removed. Reload (⌘R) covers the cases the watcher cannot
see, such as a file replaced underneath you. See
[Live reload](../features/rendering.md#live-reload).

![The open document in Reader.md re-rendering as the file changes on disk](../assets/screenshots/rendering/04-reload.mp4)

## Any editor: Helix, Zed, Sublime Text

Reader.md does not care which editor wrote the file. Helix, Zed, Sublime Text,
MacVim, and Neovide all save to disk, so all of them get the same preview with
no setup beyond adding the folder. Running `reader <file.md>` from the editor's
terminal or shell command opens the file you are working on.

## Diagrams and math

Reader.md draws fenced `mermaid` blocks as diagrams and renders LaTeX math with
KaTeX, plus syntax highlighting for code. All three engines are bundled with
the app, so the preview works offline, and a diagram that fails to parse shows
its error in place rather than breaking the page. See [Diagrams and math](../features/rendering.md#diagrams-and-math).

![A Mermaid diagram and LaTeX math rendered by Reader.md](../assets/screenshots/rendering/03-diagram.png)

## Move around the preview from the keyboard

Reader.md has a shortcut for most of what you need while reading alongside an
editor:

| Action | Shortcut |
|---|---|
| Quick Open, across every added folder | ⌘P |
| Toggle Outline | ⇧⌘B |
| Find in Page | ⌘F |
| Toggle Sidebar | ⌘B |
| Back to the previous document | ⌘[ |

Typing `#` in Quick Open lists the open document's headings to jump to. See
[Quick Open](../features/library.md#quick-open).

## How to jump back from the preview to the editor

The open in editor command (⇧⌘E) hands the open document to an app you choose
once, in **Settings ▸ Editing & Export**, with **File → Set Default Editor…**,
or by right-clicking a file and choosing **Always Open With**. That suits GUI
editors such as Zed, Sublime Text, MacVim, or Neovide.

For Neovim or Helix running in a terminal, ⇧⌘E does not return you to the
session you already have open; switching back to that terminal window is the
quicker way.
⇧⌘E is unavailable for piped documents and for files in remote folders. See
[Hand the document to an editor](../features/exporting.md#hand-the-document-to-an-editor).

## Does Reader.md change my file?

No. Reader.md never writes to your markdown; it only reads it. Highlights and
notes you add in Reader.md are stored separately on your Mac.

For more on the terminal side, see
[Render markdown from the terminal in a Mac window](render-markdown-from-terminal.md).

## Get Reader.md

Reader.md is a free, open-source (MIT) markdown viewer for macOS 13 or later on
Apple silicon. Install it with Homebrew or the DMG — see
[Install](../install.md).
