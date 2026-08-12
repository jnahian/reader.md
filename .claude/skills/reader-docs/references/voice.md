# Voice

**This file outranks the vendored skills.** `vendored/copy-editing` and
`vendored/product-marketing` come from a marketing skill set and speak in terms
of conversion, benefits, and driving action. Use their mechanics — plain
English, one idea per sentence, cutting hedges — and drop everything else. If
their guidance and this file disagree, this file wins.

Match the existing documentation rather than inventing a tone. The app's own
docs are direct, second person, and unhedged.

- **Second person.** "You add a folder", not "the user adds a folder".
- **Name controls exactly as rendered**, in bold: **Add Remote**, **Unstaged**.
- **Shortcuts in parentheses after the label** — "Toggle outline (⇧⌘B)", never
  "press ⇧⌘B to toggle the outline". This is a house convention; follow it.
- **Say what it does before why it is nice.** No feature-marketing adjectives —
  no "powerful", "seamless", "beautiful".
- **Short sentences.** One idea each.
- **State limits plainly.** If something is unavailable for remote folders or
  the bundled help docs, say so in the same paragraph as the feature.
- **No internal vocabulary.** No type names, source paths, or ticket numbers.
  `AppState` means nothing to a reader.
- **Never document unverified behaviour.** If you have not seen it in the app,
  it does not go on the page.

## Modifier glyphs

Write them as glyphs, in Apple's order: ⌃ ⌥ ⇧ ⌘. So ⇧⌘B, never ⌘⇧B or
"Cmd+Shift+B". Arrow and special keys as glyphs too: ↑ ↓ ⏎ ⎋.

**The canvas-width shortcut needs a doubled backslash.** Written as `(⇧⌘\)`,
markdown reads `\)` as an escaped parenthesis, swallows the backslash, and the
page renders "(⇧⌘)". Write `(⇧⌘\\)` — in prose and in image alt text alike.
This is invisible to every automated check; it was caught by looking at the
rendered page, which is why gate 2 includes doing that.

## What the reader already knows

They are a Mac user reading about a markdown viewer. Do not explain what
markdown is, what a sidebar is, or what a keyboard shortcut is. Do explain
anything specific to this app: what a *root* is, what the diff *scope* compares,
why a remote folder is read-only.
