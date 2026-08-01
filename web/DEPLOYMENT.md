# Deployment — Cloudflare Pages

The site is a static Astro build (`dist/`) hosted on Cloudflare Pages, served at
[reader-md.jnahian.me](https://reader-md.jnahian.me) (the `site` value in `astro.config.mjs`).

## Deploys are automatic

The GitHub repo is connected to the Pages project, so **Cloudflare rebuilds and
publishes on every push to `main`** — pushing a change under `web/` is the
deploy. Nothing to run by hand.

The dashboard settings that make it work, since the site lives in a
subdirectory (**Pages → reader-md-web → Settings → Builds**):

| Setting | Value |
|---|---|
| Root directory | `web` |
| Build command | `npm run build` |
| Build output directory | `dist` |

Run `npm run build` locally before pushing anyway: `src/data/*.ts` is typed, so a
malformed entry fails there rather than in Cloudflare's build.

## Custom domain

One time, in the Cloudflare dashboard: **Pages → reader-md-web → Custom domains →
Set up a custom domain** → `reader-md.jnahian.me`. Cloudflare adds the DNS
record automatically if the zone is on your account.

## Fallback: direct upload with wrangler

For republishing without a commit — a rolled-back build, or a deploy while the
Git integration is broken. Authenticate once (opens a browser OAuth flow):

```bash
npx wrangler login
```

Then build and upload `dist/`:

```bash
cd web
npm run build
npx wrangler pages deploy dist --project-name=reader-md-web
```

Note this publishes whatever is in your working tree, so the live site can end
up ahead of (or behind) `main` until the next push re-syncs it.
