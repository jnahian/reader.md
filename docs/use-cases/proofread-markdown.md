---
title: Proofread Markdown Before You Publish
order: 14
summary: "Read your markdown draft rendered, as readers will see it: reading themes, light and dark, word count, find, notes on the text and live reload. Free for Mac."
related: [reading, settings, annotations, exporting]
---

# Proofread markdown the way your readers will see it

Reader.md is a free markdown viewer for Mac that shows your draft rendered,
the way readers will see it, while you keep writing in your own editor.
Reader.md never edits the file: you read the page, mark what needs fixing, fix
it in your editor, and watch the page re-render.

## How do I preview markdown before publishing?

Open the draft in Reader.md with **Open File…** (⌘O), drop it on the window, or
run `reader draft.md` from a terminal. Reader.md renders the markdown as a page,
and if you add the folder the draft lives in with **Add Folder** (⇧⌘A), every
save in your editor re-renders the open page where it stands.

That pairing is the whole workflow: your editor on one side, the rendered page
on the other. See [Live reload](../features/rendering.md#live-reload).

## Why proofread the rendered version instead of the raw markdown?

Readers never see the markdown source, so mistakes that only show once it
renders are the ones that reach them. A table with a missing pipe, a list that
breaks into a paragraph, or a heading that ran into the line above all look
fine in the source and wrong on the page.

Reading the rendered draft also changes how the text looks to you. Typos hide
in prose you have stared at for an hour in your editor's font, and a different
layout makes them easier to spot.

![A markdown document rendered in Reader.md's reading canvas](../assets/screenshots/reading/01-document.png)

## How long will my post take to read?

Reader.md shows the word count and an estimated reading time in the title bar,
under the file name. A progress bar under the toolbar fills as you scroll, so
you can see how far into a long draft you are. See
[The reading canvas](../features/reading.md#the-reading-canvas).

## Change the typeface to catch more

A reading theme restyles the page without touching the file. Reader.md offers
three:

- **Standard** — the default
- **Editorial** — a serif face on a warmer ground, for long prose
- **Terminal** — everything in a monospaced face

Switching from the font you wrote in to Editorial is an old proofreading trick
in a new form: the words look unfamiliar, so you read them rather than
recognise them. Text size runs from 70% to 160% (⌘+, ⌘−, ⌘0) if you want the
page larger still. See [Reading themes](../features/settings.md#reading-themes).

![The Editorial reading theme in Reader.md, serif text on a warmer ground](../assets/screenshots/settings/03-editorial.png)

## Check it light and dark

Reader.md's appearance is **Light**, **Dark**, or **System**, set from the
toolbar button or Settings (⌘,). Flip between them to see how images, code
blocks, and tables read on both grounds before your post meets readers who use
either. See [Appearance](../features/settings.md#appearance).

## Find every instance of a word

Find in Page (⌘F) counts the matches as you type and highlights all of them,
with the current one tinted stronger. Step through them with Find Next (⌘G) and
Find Previous (⇧⌘G) to check a repeated word, a name spelled two ways, or a
term you meant to replace everywhere. See
[Finding text in a document](../features/reading.md#finding-text-in-a-document).

![In-page find in Reader.md, with the match count and step controls](../assets/screenshots/reading/03-find.png)

## Mark what to fix

Select text and Reader.md offers five highlight colours and a note button.
Highlight a clumsy sentence, attach a note saying what to change, and mark the
thread **Resolve**d once it's fixed. Reader.md stores marks on your Mac under
`~/Library/Application Support/Reader.md/` and never writes them into the
draft, so nothing stray ends up in what you publish.

Marks are anchored to their words, so fixing one paragraph leaves the marks on
the others in place. See [Highlights and notes](../features/annotations.md).

## Fix it and see it

Choose your editor once in **Settings ▸ Editing & Export**, and the open in
editor command (⇧⌘E) hands the draft straight to it. Save there, and Reader.md
re-renders the page with your scroll position kept, so you land back on the
sentence you just fixed. See
[Hand the document to an editor](../features/exporting.md#hand-the-document-to-an-editor).

## What Reader.md doesn't check

Reader.md is a reader, not a checker. Reader.md has no spelling, grammar,
style, or readability tools and does not test links; it shows you the page and
leaves the judging to you. If you use Marked 2, a paid previewer that adds
readability scores and highlights word repetition, those tools have no
equivalent in Reader.md.

## Related workflows

If your drafts are blog posts with YAML frontmatter, see
[Preview blog posts and their frontmatter on your Mac](preview-markdown-frontmatter.md).
For a README you are about to push, see
[Preview READMEs and repo docs on your Mac before you push](preview-readme-mac.md).

## Get Reader.md

Reader.md is a free, open-source (MIT) markdown viewer for macOS 13 or later on
Apple silicon. Install it with Homebrew or the DMG — see
[Install](../install.md).
