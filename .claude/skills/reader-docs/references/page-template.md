# Page Template

Structure for every `docs/features/<slug>.md`. Sections marked *(omit if none)*
are dropped, not left empty.

```markdown
---
title: Reading a document
category: Guides
order: 10
summary: The outline, in-page find, typography, and canvas width.
related: [features, cli, install]
---

# Reading a document

One or two sentences on what this page covers and who needs it.

## <Feature name>

What it does and why you'd reach for it, in a short paragraph. Name the control
exactly as it appears in the UI, and put the shortcut in parentheses after the
label — "Toggle outline (⇧⌘B)".

![Caption describing the state](../assets/screenshots/reading/01-outline.png)

Any behaviour the screenshot cannot show — what persists, what it interacts
with, when it is unavailable.

## <Feature that is a motion>

Prose first, describing what happens. A clip does not render in Reader.md or on
GitHub, so the prose must stand alone.

![Cycling the canvas width (⇧⌘\\)](../assets/screenshots/reading/05-width.mp4)
```

**There is no `## Related` section.** The card row at the foot of every page is
built from the `related` frontmatter — a hand-written list would duplicate it.
End on prose instead, if the page needs an outro at all.

Rules:

- One screenshot per meaningful state — not one per paragraph.
- Every clip is preceded by prose describing what it shows.
- Never document behaviour you have not seen in the app.
- Headings become the in-page nav, and only `##` levels appear there. If a page
  needs `###`, it is probably two pages.

## Frontmatter

All of `title`, `category`, `order`, and `summary` are required and
schema-checked — a missing one fails `npm run build`.

| Field | Notes |
|---|---|
| `title` | Match the page's `#` heading, or the sidebar and the body disagree |
| `category` | Feature pages are **Guides**. The others in use: Getting started, Reference, Internals. A new value creates a new group — reuse before inventing |
| `order` | Global sort across every docs page, not per category. Guides sit in the 10s; leave gaps |
| `summary` | One line. It is the card text on `/docs` *and* the page's meta description, so write it to stand alone |
| `related` | Ids of 2–3 pages to offer at the foot. Ids, not URLs — an unknown or self-referential one fails the build by name |

`docs/features/<slug>.md` publishes at `/docs/<slug>`, so **a slug that collides
with a root-level page fails the build**. `install`, `features`, `cli`,
`architecture`, and `building` are taken. To document the CLI in depth, extend
`docs/cli.md` rather than adding `docs/features/cli.md`.
