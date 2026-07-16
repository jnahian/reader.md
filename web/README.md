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

Static site hosted on **Cloudflare Pages**. See [DEPLOYMENT.md](./DEPLOYMENT.md).

```bash
npm run build && npx wrangler pages deploy dist --project-name=reader-md-web
```

## Structure

```
web/
├─ public/icon.png            app icon (favicon + OG image)
├─ src/
│  ├─ styles/global.css       design tokens, base styles, keyframes, shared utilities
│  ├─ data/
│  │  ├─ site.ts              links, commands, nav config
│  │  ├─ content.ts           feature/shortcut/CLI/architecture data (from README.md)
│  │  └─ changelog.ts         release history (from Sources/.../docs/CHANGELOG.md)
│  ├─ layouts/Base.astro      <head>, nav, footer, background blobs, shared scripts
│  ├─ components/             Nav, Footer, Hero, FeatureGrid, showcases, ChangelogEntry, …
│  └─ pages/
│     ├─ index.astro          landing
│     ├─ docs.astro           documentation
│     ├─ changelog.astro      release notes
│     └─ 404.astro
```

## Conventions

- **Design tokens** (colours, fonts, spacing) live as CSS custom properties in
  `src/styles/global.css`. Reusable patterns — `.card`, `.pill`, `.btn`, `.eyebrow`,
  `.tok`, chips, and syntax-token colours — are defined there once and shared.
- **Component styles** are scoped `<style>` blocks that reference those tokens, so
  a colour or radius changes in exactly one place.
- **Content** is data-driven: prose from the repo `README.md` lives in `data/content.ts`
  and release notes in `data/changelog.ts`, kept in sync with the app's bundled changelog.
- **Motion** (scroll-reveal, parallax, typing) is progressive and fully disabled under
  `prefers-reduced-motion`.
