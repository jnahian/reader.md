# CLAUDE.md — web

Guidance for the marketing site. The root `CLAUDE.md` covers the macOS app;
this file covers only `web/`. Setup, commands, and file layout are in
[README.md](./README.md) — not repeated here.

## The site is downstream of the app

Nothing in `src/data/` is a source of truth. Both files mirror something in the
repo above, so **edit the source first, then mirror it down**:

| Site file | Mirrors |
|---|---|
| `src/data/content.ts` | `docs/features.md`, `docs/cli.md`, `docs/architecture.md` in the repo root |
| `src/data/changelog.ts` | `Sources/ReaderMd/Resources/docs/CHANGELOG.md` |

A feature described on the site but not in the app's own docs is a bug in the
site. When a shortcut or behaviour changes, the app's `Resources/docs/` files
(`SHORTCUTS.md`, `FAQ.md`, `CHANGELOG.md`) are authoritative — and the real
authority is `ReaderMdApp.swift`, where the `.keyboardShortcut` bindings live.

## changelog.ts is per release, never per merge

Add an entry when a version is **released**, not when a feature merges — one
`Release` per shipped version, matching the `## [version]` section of the app's
`CHANGELOG.md`, with `date` set to the release date. Existing commits follow
`docs(web): add <version> to the site changelog`.

Keep-a-Changelog headings map onto the site's three buckets:

| CHANGELOG.md | `Tag` |
|---|---|
| `### Added` | `ADDED` |
| `### Changed` | `IMPROVED` |
| `### Fixed` | `FIXED` |

Put the new entry **first** — the list is ordered newest-first, and the "latest"
pill in the changelog header reads `releasesLog[0].version`, so a misordered list
mislabels the header. Move the `badge: "LATEST"` to the new entry and drop it
from the previous one.
`items` are HTML strings rendered with `set:html` — a bolded lead-in, then an
em dash, then the prose (see any existing entry).

There is no "Unreleased" release on the site. Work that has merged but not
shipped belongs in the app's `CHANGELOG.md` only.

## Constraints

- **No UI or CSS framework.** Plain `.astro` components with scoped `<style>`
  blocks over the custom properties in `src/styles/global.css`. Don't reach for
  Tailwind, a component library, or a client-side framework — there is no
  client-side JS framework here on purpose, and shared patterns (`.card`,
  `.pill`, `.btn`, `.tok`) already exist in `global.css`.
- **Colours, radii, and spacing come from tokens**, so a change lands in one
  place. A hard-coded hex in a component is a mistake.
- **Motion is optional.** Scroll-reveal, parallax, and typing effects must stay
  behind `prefers-reduced-motion`.
- **Deploys are automatic** — Cloudflare Pages builds and publishes when a push
  to `main` touches `web/`, so a site edit that lands goes live on its own.
  Treat anything you push under this directory as published; a commit outside it
  deploys nothing, and no branch other than `main` deploys at all. `wrangler
  pages deploy` remains as a fallback for republishing without a commit, per
  [DEPLOYMENT.md](./DEPLOYMENT.md).

## Verify

`npm run build` is the check that matters — `src/data/*.ts` is typed, so a
malformed entry fails the build rather than rendering wrong. Run it after any
data edit.
