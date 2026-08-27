---
title: Reading a document
category: Guides
order: 12
summary: The outline, in-page find, text size, and canvas width.
related: [library, features, cli]
---

# Reading a document

Four things shape how a document reads: the canvas it lays out in, the outline
beside it, finding a phrase within it, and how large the text is. Each has a
keyboard shortcut, and every setting on this page persists across launches — set
it once and every document you open afterwards inherits it.

## The reading canvas

Open a file from the sidebar, with Quick Open (⌘P), or by dropping it onto the
window, and it renders in the canvas. The title bar carries the file name, the
word count, and an estimated reading time; a progress bar under the toolbar
fills as you scroll.

![A document open in the reading canvas](../assets/screenshots/reading/01-document.png)

Close the document with ⌘W, or with the floating × at the top of the canvas.
Closing leaves the window and the sidebar as they are — it is the document that
closes, not the app.

## The outline

Toggle the outline (⇧⌘B) to get the document's heading structure in a pane on
the right. It tracks your position as you scroll, with an accent rail marking
the heading you are inside, and clicking any entry jumps to it.

![The outline pane, opened with ⇧⌘B](../assets/screenshots/reading/02-outline.png)

Nested headings indent, so the pane shows at a glance how deeply a document is
structured. In diff mode (⇧⌘D) the outline lists changed hunks instead of
headings.

## Finding text in a document

Find in Page (⌘F) opens a search field in the toolbar. It counts the matches as
you type and highlights all of them, tinting the current match a stronger colour
than the others so you can see where you are in the document.

![In-page find, with the match count and step controls](../assets/screenshots/reading/03-find.png)

Step through matches with the chevrons beside the count, with ⌘G and ⇧⌘G, or
with ⌘↩ and ⇧⌘↩. Press ⎋ to clear the field.

This searches inside the open document. To search *across* files instead, filter
the sidebar (⇧⌘F) or use Quick Open (⌘P).

## Text size

Make the text bigger (⌘+), smaller (⌘−), or reset it to the default (⌘0). The
size applies to every document, not only the open one, and survives a restart.

![Text size increased two steps with ⌘+](../assets/screenshots/reading/04-typography.png)

## Canvas width

Cycle the canvas width (⇧⌘\\) through three settings: **Narrow** for a tight
measure, **Wide** for a comfortable one, and **Full Width** to use the whole
window. Wide is the default. The clip below cycles from Wide to Full Width to
Narrow, showing how the text column reflows at each step.

![Cycling the canvas width (⇧⌘\\)](../assets/screenshots/reading/05-width.mp4)

Width and text size work together: a narrow canvas with larger text gives the
short line length of a book, while full width with smaller text suits wide
tables and long code blocks.

## Focus mode

**⌥⌘F** takes everything away except the page. The sidebar and outline
collapse, the toolbar goes, the window moves to fullscreen, the canvas
narrows, and every section but the one you're reading dims. The toolbar's
focus button and `>Focus Mode` in ⌘P do the same thing.

**⌥⌘F again, or ⎋, brings it all back** — and back means back: the sidebar,
outline, and column width return to what they were, not to a default. ⎋
stays polite about it, clearing an active search or dismissing ⌘P first, and
only leaves focus mode once there's nothing else to dismiss. Leaving
fullscreen with the green traffic-light button exits it too, since focus mode
doesn't outlive the fullscreen it's running in. (If the window was
already in fullscreen before ⌥⌘F, exiting focus mode leaves it there rather
than dropping out.)

The dimming follows the outline rather than the scroll position, so it holds
still while you read a section and fades across when you reach the next
heading. **Region ends at** in Settings decides how wide "a section" is: every
heading by default, or only headings down to H3, H2 or H1 — at *H2 or above* an
`h2` stays lit across all of its subheadings, and crossing one of them changes
nothing. A document whose headings are all deeper than that setting has no
regions to tell apart, so nothing dims. **Dimming** sets how far the rest fades,
from 40% to 88%. Dimming steps aside entirely while you're searching, in diff
mode, and in a document with fewer than two headings.

⌘F still works: rather than dropping you out of focus mode, it slides the
toolbar back down with the find field ready, and the toolbar stays down until
you leave focus mode.

Settings (⌘,) has a switch for each of the four pieces — fullscreen, dimming,
narrow canvas, hidden toolbar — all on by default, so you can keep only the
parts you want. Hiding the toolbar behaves the same whether or not fullscreen
is on, and the toolbar is never far away: nudge the pointer to the top edge of
the screen and it slides back down for as long as you're up there — long enough
to reach a control and click it. ⌘F brings it down too, and keeps it down while
you search. Neither costs you focus mode.

Focus mode never persists. However you leave the app, it starts up outside it.

For everything else Reader.md does — Quick Open, the file filter, diagrams, math
— and every binding in one table, see [Features](../features.md).
