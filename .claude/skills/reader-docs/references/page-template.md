# Page Template

Structure for every `docs/features/<slug>.md`. Sections marked *(omit if none)*
are dropped, not left empty.

```markdown
---
title: Reading a document
order: 4
summary: The outline, in-page find, typography, and canvas width.
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

![Cycling the canvas width (⇧⌘\)](../assets/screenshots/reading/05-width.mp4)

## Related          (omit if none)

Links to the other pages a reader would want next.
```

Rules:

- One screenshot per meaningful state — not one per paragraph.
- Every clip is preceded by prose describing what it shows.
- Never document behaviour you have not seen in the app.
- Frontmatter `order` sets the position in the docs nav. `title` and `summary`
  are required and schema-checked: a missing one fails `npm run build`.
- Headings become the in-page nav, and only `##` levels appear there. If a page
  needs `###`, it is probably two pages.
