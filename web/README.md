# Reader.md — web

The marketing site for Reader.md: a dark, "Liquid Glass" landing page, docs, and
changelog, built with [Astro](https://astro.build). No UI framework and no CSS
framework — plain `.astro` components with scoped styles over a small set of
design tokens.

## Develop

```bash
cd web
npm install
npm run dev      # http://localhost:4321
npm run build    # static output → dist/
npm run preview  # serve the build
```

## Deploy

Static site hosted on **Cloudflare Pages**, and **deploys are automatic**:
pushing to `main` a commit that touches `web/` or `docs/` builds and publishes
the site. There is no manual step — see [DEPLOYMENT.md](./DEPLOYMENT.md) for the
project settings and the build-watch paths.

`wrangler` stays available for republishing without a commit:

```bash
npm run build && npx wrangler pages deploy dist --project-name=reader-md-web
```

## Structure

```
web/
├─ plugins/
│  ├─ docs-pages.mjs          which ../docs/*.md publish, and the URL each gets
│  └─ remark-docs-assets.mjs  rewrites .md links + screenshot paths at build time
├─ public/
│  ├─ icon.png                app icon (favicon + OG image)
│  └─ screenshots/            GENERATED — `prebuild` copies ../docs/assets/screenshots
├─ src/
│  ├─ styles/global.css       design tokens, base styles, keyframes, shared utilities
│  ├─ content.config.ts       the `docs` collection, loaded from ../docs/
│  ├─ data/
│  │  ├─ site.ts              links, commands, nav config
│  │  ├─ content.ts           landing-page copy (highlight cards, shortcut strip)
│  │  └─ changelog.ts         release history (from Sources/.../docs/CHANGELOG.md)
│  ├─ layouts/Base.astro      <head>, nav, footer, background blobs, shared scripts
│  ├─ components/             Nav, Footer, Hero, FeatureGrid, showcases, DocsNav,
│  │                          RelatedDocs, KeyboardCli, Icon, FinalCta, ChangelogEntry
│  └─ pages/
│     ├─ index.astro          landing
│     ├─ docs.astro           docs hub — card grid built from the collection
│     ├─ docs/[...slug].astro every docs page, rendered from ../docs/*.md
│     ├─ changelog.astro      release notes
│     └─ 404.astro
```

`public/screenshots/` is **generated, and gitignored**: `npm run prebuild` deletes
it and re-copies `../docs/assets/screenshots/`. Edit an image there and the next
build throws the work away — the originals live in `docs/assets/screenshots/`,
captured by the `reader-docs` skill from a `.shots.json` manifest.

## Conventions

- **Design tokens** (colours, fonts, spacing) live as CSS custom properties in
  `src/styles/global.css`. Reusable patterns — `.card`, `.pill`, `.btn`, `.eyebrow`,
  `.tok`, chips, and syntax-token colours — are defined there once and shared.
- **Component styles** are scoped `<style>` blocks that reference those tokens, so
  a colour or radius changes in exactly one place.
- **Content lives above `web/`.** The `/docs/` pages render the repo's `docs/*.md`
  and `docs/features/*.md` directly, so that prose has exactly one copy; only the
  landing-page copy (`data/content.ts`) and the release notes (`data/changelog.ts`,
  mirroring the app's bundled changelog) are data files here. See
  [CLAUDE.md](./CLAUDE.md).
- **Motion** (scroll-reveal, parallax, typing) is progressive and fully disabled under
  `prefers-reduced-motion`.
