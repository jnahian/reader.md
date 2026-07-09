# Reading Themes — Design

**Status:** approved, not implemented
**Covers:** original request item 4

## Problem

The content pane has exactly two appearances — light and dark — hardcoded as
`:root` and `html.dark` CSS variable blocks in `template.html`. There is no way to
change the reading typeface or the palette family.

## Model

**Theme and mode are orthogonal.** A *mode* is light or dark, chosen with the
existing ☀/☽ toggle. A *theme* is a family that defines **both** of its modes.
Picking "Editorial" and then toggling to dark yields Editorial-dark, not
generic dark.

```
Theme:  Default | Editorial | Terminal
Mode:   Light   | Dark
        → 6 combinations, all of which must render.
```

A theme is a CSS variable block plus a font stack plus a highlight.js stylesheet
pair. Nothing more. It is not a user-editable theming engine; the set is curated
and fixed.

**Chrome is out of scope.** The sidebar, topbar, and outline keep their system
appearance and Liquid Glass materials. Tinting them to the theme accent was
considered and cut: the chrome reads its accent from `Color.accentColor` at nine
call sites (`SidebarView` ×3, `TOCView` ×2, `FileTreeRow` ×2, `QuickOpenView`,
`MarkPopoverView`, `ResolvedThreadsToggle`), and `Color.accentColor` resolves the
*system* accent — it ignores the `\.tint` environment value, so a single `.tint()`
modifier on `ContentView` would do nothing. Nine edits across six view files for
a tint is not worth it. The content pane carries the personality.

## Naming

`AppTheme` currently means light/dark. Once real themes exist that name is
actively misleading. Rename it:

- `AppTheme` → `AppearanceMode` (15 call sites; mechanical)
- new `ReadingTheme: String, CaseIterable { case standard, editorial, terminal }`

The rename does not touch persisted `rawValue`s (`"light"` / `"dark"`), so
existing `UserDefaults` entries keep loading. `standard` rather than `default`
because `default` is a Swift keyword.

## Themes

| Theme | Light bg / fg | Dark bg / fg | Body font | Accent |
| --- | --- | --- | --- | --- |
| Standard | `#ffffff` / `#1f2328` | `#1e2228` / `#e6edf3` | system sans | `#0969da` / `#4493f8` |
| Editorial | `#fbf7f0` / `#2b2724` | `#22201d` / `#ece5d8` | New York, ui-serif, Georgia | `#8a4b2a` / `#e0a458` |
| Terminal | `#ffffff` / `#101418` | `#0b0e11` / `#d5e0d5` | ui-monospace, SF Mono | `#0a7a33` / `#3fb950` |

**Standard's two blocks are today's values verbatim, so existing users see no
change on upgrade.** Exact palette values for the other two are a starting point,
to be tuned against real documents during implementation.

System fonts only. No bundled webfonts — the app stays offline and small.

## Changes

**`template.html`**
Add two variables to every block — `--font-body`, `--font-mono` — consumed by
`body { font-family: var(--font-body) }` and `code { font-family: var(--font-mono) }`.
Headings inherit from `body`, so Editorial gets serif headings for free.

Extend the existing variable scoping from two blocks to six:

```css
:root { /* Standard light — today's values */ }
html.dark { /* Standard dark — today's values */ }

html[data-theme="editorial"] { … }
html[data-theme="editorial"].dark { … }
html[data-theme="terminal"] { … }
html[data-theme="terminal"].dark { … }
```

Standard sets no `data-theme` attribute, so `:root` / `html.dark` continue to
serve it and specificity resolves without `!important`.

**Syntax highlighting.** Today `bridge.js` toggles `disabled` on two fixed
`<link>` tags (`#hljs-light`, `#hljs-dark`). Keep both tags and the `disabled`
toggle for mode — swapping a single link's `href` on mode change would flash.
Instead, set **both `href`s** when the theme changes, from a lookup table:

```js
const HLJS = {
  standard:  ['styles/github.min.css',            'styles/github-dark.min.css'],
  editorial: ['styles/atom-one-light.min.css',    'styles/atom-one-dark.min.css'],
  terminal:  ['styles/stackoverflow-light.min.css','styles/stackoverflow-dark.min.css'],
};
```

Adds four highlight.js stylesheets (~2 KB each) to `Resources/web/styles/`.

**`bridge.js`**

```js
window.ReaderMd.setReadingTheme = function (name) {
  // Standard must *remove* the attribute, not set it empty — `html[data-theme=""]`
  // would still match an attribute selector.
  const root = document.documentElement;
  if (name === 'standard') delete root.dataset.theme;
  else root.dataset.theme = name;
  const [light, dark] = HLJS[name] || HLJS.standard;
  document.getElementById('hljs-light').href = light;
  document.getElementById('hljs-dark').href = dark;
  initMermaid();
  if (window.__lastMarkdown != null) render(window.__lastMarkdown, currentDir, true);
};
```

This mirrors the existing `setTheme(dark)` exactly — same `initMermaid()` +
scroll-preserving re-render path. Mermaid has only `'dark'` and `'default'`
built-in themes, so Editorial and Terminal use whichever matches the current mode.
Accepted limitation; diagrams are not themed per reading theme.

**`Settings.swift`**
`reader.md.readingTheme`. Load returns `.standard` when the key is absent **or
holds an unknown name**, so removing a theme in a future version cannot brick
startup.

**`AppState.swift`**
`@Published var readingTheme: ReadingTheme`, a `setReadingTheme(_:)` that persists
and triggers the bridge call. `AppTheme` → `AppearanceMode` rename.

**`MarkdownWebView.swift`**
Call `setReadingTheme` on `readingTheme` change, alongside the existing `setTheme`
call. On first `ready`, push both.

**`TopBar.swift`**
A `Theme` section at the top of the existing `textformat.size` menu, above the
text-size items, with a checkmark on the active theme:

```
Theme
 ✓ Standard
   Editorial
   Terminal
 ───────────────
 Increase Text   ⌘+
 Decrease Text   ⌘−
 Actual Size     ⌘0
 ───────────────
 ✓ Wide Reading Column
```

No new topbar button. The right-hand capsule is already gaining a search icon
from the find-in-page work.

## Consequences

PDF export renders through the same stylesheet, so ⌘E produces a themed PDF.
Editorial-dark exports a dark PDF. This is consistent with how the light/dark
toggle already behaves; call it out in the release notes rather than special-casing.

## Verification

1. All six theme × mode combinations render; no unstyled flash on switch
2. A document with a code block, a Mermaid diagram, a LaTeX expression, a table,
   and a blockquote survives every one of the six
3. Switching theme preserves scroll position (the `keepScroll` re-render path)
4. Syntax highlighting swaps with the theme, and still swaps with the mode
5. Theme survives an app restart
6. A persisted `readingTheme` of `"nonexistent"` → falls back to Standard, no crash
7. A user upgrading with an existing `reader.md.theme` of `"dark"` → lands on
   Standard-dark, visually identical to before the change
8. ⌘+ / ⌘− still scale text in every theme
9. Editorial's serif applies to headings and body but **not** to code blocks
