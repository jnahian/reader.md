---
title: Preview README Files on Mac Before You Push
order: 2
summary: See READMEs and repo docs rendered GitHub-style on your Mac, with Mermaid, LaTeX, code and local images, live reload and a folder sidebar. Free, no push needed.
related: [rendering, library, reading, cli]
---

# Preview READMEs and repo docs on your Mac before you push

Reader.md is a free, native Mac app that shows a `README.md` and the rest of a
repo's markdown rendered GitHub-style, before you commit or push anything. Open
the repo folder, keep your editor beside it, and Reader.md re-renders every time
you save — with Mermaid diagrams, LaTeX math, highlighted code and images drawn
in place, all offline.

![A README-style document in Reader.md with a table, highlighted code, a Mermaid diagram and math](../assets/screenshots/rendering-showcase/01-rendering.png)

## How do I see what my README will look like on GitHub?

Open the file in Reader.md: `reader README.md` from the repo, or drag it onto
the window. Reader.md renders GitHub-flavoured markdown — tables, footnotes,
task lists and fenced code — so headings, lists, tables and code blocks come out
the way they will on GitHub.

Be clear about the limit: Reader.md is close to GitHub, not a pixel copy of it.
Reader.md parses markdown with its own bundled renderer and styles the page with
its own reading themes, so spacing and fonts differ from github.com. GitHub-only
extras such as alert blocks (`> [!NOTE]`) and emoji shortcodes (`:tada:`) are
not part of what Reader.md renders. Use Reader.md to catch broken structure,
bad tables, unclosed fences and typos before a push; use GitHub itself for the
final pixel check.

See [How a document is rendered](../features/rendering.md).

## How to view a README.md rendered on Mac without an editor

Reader.md is a reader, not an editor, so viewing a rendered README needs nothing
else installed — no VS Code, no browser, no local server. Ways to open one:

- `reader README.md` — one file from the terminal
- `reader .` — the whole repo you are standing in, added to the sidebar
- ⌘O, Finder, or dragging a file onto the window
- Setting Reader.md as the Finder default for `.md` files

The `reader` command comes with the Homebrew install, or from
**File → Install `reader` Command Line Tool…**. Every verb is in the
[command-line reference](../cli.md).

To make Reader.md what a double-click in Finder opens, see
[How to open .md files on a Mac, rendered instead of raw](open-md-files-on-mac.md).

## Live reload markdown preview on Mac

Reader.md watches every folder you add. Save the README in your editor and the
open document re-renders where it stands, scroll position kept, so a long file
does not jump back to the top. Open in Editor (⇧⌘E) hands the current document
to the editor you choose in Settings, and every save comes straight back — the
two side by side behave like a live preview. Reload (⌘R) covers the rare change
the watcher cannot see.

![The open document re-rendering as the file changes on disk](../assets/screenshots/rendering/04-reload.mp4)

See [Live reload](../features/rendering.md#live-reload).

## Does Mermaid render in a local markdown preview?

Yes. In Reader.md, a code fence tagged `mermaid` is drawn as a diagram, and
LaTeX math renders inline (`$…$`) and as display blocks (`$$…$$`). Diagrams get
zoom, reset and fullscreen controls on hover, and a diagram that fails to parse
shows its error in place instead of breaking the rest of the document — useful
for catching a typo in a flowchart before GitHub shows it to everyone.

![A Mermaid diagram and LaTeX math rendered in the same document](../assets/screenshots/rendering/03-diagram.png)

Fenced code is highlighted for the language you tag, with a **Copy** button on
hover. Local images referenced by relative path, such as `docs/screenshot.png`, show in place, and clicking one opens it in a lightbox. See
[Diagrams and math](../features/rendering.md#diagrams-and-math).

## Can I preview markdown offline?

Yes. Reader.md bundles its markdown renderer, syntax highlighter, Mermaid and
KaTeX, so a README renders the same with the network off. Reader.md never sends
your markdown anywhere; its only outbound request is the update check.

## Browse a docs folder, not just the README

Most repos have more than a README: a `docs/` folder, a `CONTRIBUTING.md`, a
changelog. Reader.md shows every markdown file under the repo in a sidebar tree,
skipping `node_modules` and `.git`, and links between markdown files open in the
same window, with Back (⌘[) to return.

![The sidebar with two folders added](../assets/screenshots/library/01-sidebar.png)

- **Quick Open (⌘P)** — fuzzy-find any file by name or folder path
- **Outline (⇧⌘B)** — the heading structure of the open file, tracking your scroll
- **Filter Files (⇧⌘F)** — narrow the tree by file name across every folder

See [Finding your files](../features/library.md) and
[The outline](../features/reading.md#the-outline). If you want to review what
changed in a doc before committing, see
[Review markdown changes](review-markdown-changes.md).

## Compared with other previewers

| Tool | How it previews |
|---|---|
| grip | A Python command-line server that renders through GitHub's markdown API and serves the page at `localhost` — needs the network, and is rate-limited without a GitHub token |
| VS Code preview | Built into the editor, Mermaid included — you read inside VS Code |
| Quick Look plugins | Preview one file at a time from Finder, with no folder tree or live preview beside an editor |
| Marked 2 / Marked 3 | A paid Mac previewer, with a seven-day trial |
| Reader.md | Free (MIT), native, offline, a folder sidebar, Mermaid and math built in |

Reader.md is the choice when you want a free, offline grip alternative or VS Code
markdown preview alternative that stays open beside whatever editor you use.

If you are weighing Typora, see
[A free Typora alternative for when you only read markdown](typora-alternative-for-reading.md).

## Get Reader.md

Reader.md is free and MIT-licensed, for macOS 13 or later on Apple-silicon Macs.
Install it with Homebrew or download the DMG — see [Install](../install.md).
