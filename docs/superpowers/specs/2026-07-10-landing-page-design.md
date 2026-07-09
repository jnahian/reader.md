# Reader.md Landing Site — Design

**Date:** 2026-07-10
**Status:** Approved

## Goal

A marketing/landing site for the Reader.md macOS app: sell the app, make install
trivial, and surface the bundled docs (changelog, FAQ, shortcuts). Built with
Astro, styled with Tailwind CSS. **No gradients anywhere** — flat colors only.

## Decisions (from brainstorming)

| Decision | Choice |
|---|---|
| Hosting | Vercel or Netlify (root directory `site/`, Astro preset, static output) |
| Location | `site/` subdirectory of this repo |
| App visual | Pure-CSS mock of the app window (no screenshots) |
| Styling | Tailwind CSS v4 via `@tailwindcss/vite` |
| Structure | Multi-page: `/`, `/changelog`, `/faq`, `/shortcuts` |
| Theme | Light/dark/system with a header toggle (localStorage-persisted, cycles like the app; system follows `prefers-color-scheme`); Apple-style flat design, system font stack |
| Client JS | Two minimal inline scripts for the theme toggle only (no external JS, no frameworks) — relaxed from "none" by user request 2026-07-10 |

## Structure

```
site/
├── package.json, astro.config.mjs
├── public/                      icon.png (resized from Sources/ReaderMd/Resources/AppIcon.png), favicon
├── scripts/copy-docs.mjs        prebuild: copies markdown sources into src/generated/ (gitignored)
└── src/
    ├── layouts/Base.astro       head, nav (icon + name, page links, GitHub), footer (MIT, links)
    ├── components/
    │   ├── Hero.astro           icon, name, tagline, Download DMG + GitHub CTAs, fine print
    │   ├── AppMock.astro        CSS fake app window: traffic lights, sidebar FOLDERS tree with
    │   │                        ☁︎ remote root, rendered-markdown pane, outline rail w/ accent
    │   ├── Features.astro       9 cards (data array): open anything, remote SSH folders, live
    │   │                        reload, Mermaid/LaTeX/code, quick open & find, outline &
    │   │                        progress, Liquid Glass chrome, PDF export, private by design
    │   ├── Install.astro        brew tap/install code blocks + DMG right-click→Open note
    │   ├── Shortcuts.astro      README shortcut table as kbd rows, links to /shortcuts
    │   └── Contribute.astro     star repo, report issue / feedback, CONTRIBUTING.md pointer
    └── pages/
        ├── index.astro          composes the six sections
        ├── changelog.astro      renders generated copy of CHANGELOG.md
        ├── faq.astro            renders generated copy of Sources/ReaderMd/Resources/docs/FAQ.md
        └── shortcuts.astro      renders generated copy of Sources/.../docs/SHORTCUTS.md
```

## Data flow

- **Doc pages:** `scripts/copy-docs.mjs` runs as `predev`/`prebuild`, copying the
  three bundled markdown files (`CHANGELOG.md`, `FAQ.md`, `SHORTCUTS.md`, all in
  `Sources/ReaderMd/Resources/docs/`) into `site/src/generated/` (gitignored). Pages import the
  copies as Astro markdown. Single source of truth stays in the app repo; the
  site never reaches outside `site/` at build time.
- **Landing copy:** feature cards and shortcut rows are small const arrays in
  their components — copy edits don't touch markup.
- **Download CTA:** `https://github.com/jnahian/reader.md/releases/latest/download/Reader.md.dmg`
  (always the newest release; no version baked into the site).

## Styling

- Tailwind v4, theme tokens as `@theme` CSS variables (bg, fg, muted, accent,
  border, card) with dark values under `prefers-color-scheme: dark`.
- System font stack (`-apple-system, …`); `ui-monospace` for code.
- Flat colors only — no `linear-gradient`/`radial-gradient` anywhere.
- Doc pages use a narrow prose column with locally scoped typography styles
  (no typography plugin unless it proves necessary).

## Error handling

Static site — the only failure surface is the build. `copy-docs.mjs` fails the
build loudly if a source markdown file is missing (no silent empty pages).

## Testing / verification

- `npm run build` passes from a clean checkout of `site/`.
- Visual check of all four pages in light and dark (local `astro preview` +
  browser screenshots).
- Grep the built output for `gradient` — must be zero hits.

## Out of scope

- Custom domain / DNS
- Screenshots or demo video
- Analytics
- Blog/docs beyond the three markdown-backed pages
