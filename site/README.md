# Reader.md landing site

Astro + Tailwind static site for https://github.com/jnahian/reader.md.

## Develop

```bash
npm install
npm run dev      # copies bundled docs (predev) then serves on :4321
```

`src/generated/` holds build-time copies of the app's bundled
`CHANGELOG.md` / `FAQ.md` / `SHORTCUTS.md` (source of truth:
`../Sources/ReaderMd/Resources/docs/`). Never edit the copies.

## Deploy (Vercel or Netlify)

Import the repo and set:

- **Root directory:** `site`
- **Framework preset:** Astro (auto-detected)
- Build command `npm run build`, output `dist` (preset defaults)

Every push to `main` redeploys.
