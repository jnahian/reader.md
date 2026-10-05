---
title: Review Design Docs, RFCs and ADRs in Markdown
order: 13
summary: "Read RFCs, ADRs, and design docs as rendered markdown with diagrams, then mark up questions privately before you comment where the team decides. Free, for Mac."
related: [annotations, rendering, library, git]
---

# Read RFCs, ADRs, and design docs before you weigh in

Reader.md is a free markdown viewer for Mac that renders RFCs, architecture
decision records, and design docs the way their authors meant them to read:
diagrams drawn, math typeset, and an outline beside the text. Reader.md also
lets you highlight passages and keep threads of open questions on the document
without writing to the file, as a private first pass before you comment in the
pull request or wherever your team decides.

## How do I review an RFC?

Read the whole proposal once before commenting, then check it against a short
list: the problem it solves, the non-goals, the alternatives considered, the
risks, and the rollout plan. Each question you can't answer from the text is a
comment worth making.

Reader.md supports that first pass. Mark each gap where it appears, keep one
thread per question, and resolve threads as later sections answer them. What is
still open at the end is your review, ready to post where the discussion
happens.

## Open the RFC folder

Add the folder that holds your proposals with **Add Folder** (⇧⌘A), or run
`reader .` from the repository. Reader.md lists every markdown file beneath it
in the sidebar and watches the folder, so a proposal the author revises
re-renders where you are reading, with your scroll position kept.

Quick Open (⌘P) finds a proposal by name or by the folder it sits in, which
helps once a repository holds dozens of numbered RFCs. See
[Finding your files](../features/library.md#quick-open).

## Read an ADR log

Architecture decision records usually live in the repository itself, in a
folder such as `docs/adr` or `docs/decisions`. Add that folder to Reader.md and
the sidebar lists every record, with no site to generate and no build step.

If your ADRs carry YAML frontmatter (a status, a date, the deciders), Reader.md
renders that block as a key/value table above the record instead of raw text,
so a superseded decision says so at the top. See
[Frontmatter and tables](../features/rendering.md#frontmatter-and-tables).

## Diagrams and math in a design doc

Reader.md draws fenced `mermaid` blocks as diagrams and renders LaTeX math,
offline, from engines bundled with the app. A sequence diagram or architecture
sketch in a design doc reads as a picture rather than a code block.

Large diagrams have their own controls on hover: zoom in, zoom out, reset, and
fullscreen, which drops the width limit Mermaid puts on its own output. A
diagram that fails to parse shows its error in place and leaves the rest of the
document readable. See [Diagrams and math](../features/rendering.md#diagrams-and-math).

![A Mermaid diagram and LaTeX math rendered in the same document in Reader.md](../assets/screenshots/rendering/03-diagram.png)

## Move through a long proposal

Toggle Outline (⇧⌘B) shows the document's headings in a pane on the right,
tracks your position as you scroll, and jumps to any section you click. Typing
`#` in Quick Open (⌘P) lists the same headings to jump to from the keyboard,
and Find in Page (⌘F) counts every mention of a term. See
[The outline](../features/reading.md#the-outline).

![Reader.md's outline pane listing a document's headings beside the text](../assets/screenshots/reading/02-outline.png)

## Mark up before you comment

Select text and Reader.md offers five highlight colours and a note button.
A note turns the highlight into a thread, and replies stack under it in order,
so a question about the rollout plan can sit on the rollout section and gather
your follow-up thoughts as you read on. Used this way, threads work as a review
checklist per section.

![A mark reopened in Reader.md, showing its thread, a reply field, Delete, and Resolve](../assets/screenshots/annotations/04-thread.png)

## Resolve as questions are answered

Mark a thread **Resolve**d when a later section answers it. Reader.md keeps the
thread but de-emphasizes the mark, and a count of resolved threads appears in
the toolbar. Click the count to hide resolved marks entirely, leaving only the
questions still open. See
[Threads and resolving](../features/annotations.md#threads-and-resolving).

![A resolved thread de-emphasized in the text, with the resolved count in the toolbar](../assets/screenshots/annotations/05-resolved.png)

## Can others see my comments?

No. Reader.md stores highlights, notes, and threads on your Mac, under
`~/Library/Application Support/Reader.md/`, and never writes them into the
markdown. There are no accounts; the author on each note is your macOS full
name. Post your review in the pull request or the design doc's own venue.

## Do comments stay when the RFC is edited?

Yes, as long as the words they were made on survive. Reader.md anchors each
mark to its text, so edits elsewhere in the document leave it in place. If the
marked text is removed, the mark is flagged as orphaned rather than deleted.
Renaming or moving the file loses its marks, because the path is the key. See
[When the text moves](../features/annotations.md#when-the-text-moves).

## When the RFC is revised

In a git repository, Toggle Diff (⇧⌘D) shows what changed in the proposal as a
side-by-side diff with word-level highlights, against staged work or another
branch. Marks are hidden while the diff is showing. For that workflow, see
[Review documentation changes before they merge](review-markdown-changes.md).
If a coding agent drafted the design doc, see
[Review what your coding agent writes](review-ai-agent-docs.md).

## Get Reader.md

Reader.md is a free, open-source (MIT) markdown viewer for macOS 13 or later on
Apple silicon. Install it with Homebrew or the DMG — see
[Install](../install.md).
