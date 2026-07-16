# Deployment — Cloudflare Pages

The site is a static Astro build (`dist/`) hosted on Cloudflare Pages, served at
[reader-md.jnahian.me](https://reader-md.jnahian.me) (the `site` value in `astro.config.mjs`).

## One-time setup

Authenticate wrangler (opens a browser OAuth flow):

```bash
npx wrangler login
```

## Deploy (direct upload)

Build, then upload `dist/`:

```bash
cd web
npm run build
npx wrangler pages deploy dist --project-name=reader-md-web
```

The first run creates the `reader-md-web` Pages project and asks for a production
branch — pick `main`.

## Custom domain

One time, in the Cloudflare dashboard: **Pages → reader-md-web → Custom domains →
Set up a custom domain** → `reader-md.jnahian.me`. Cloudflare adds the DNS
record automatically if the zone is on your account.

## Alternative: Git integration

Instead of direct upload, connect the GitHub repo in the dashboard so Cloudflare
builds on every push to `main`. Because the site lives in a subdirectory, set:

| Setting | Value |
|---|---|
| Root directory | `web` |
| Build command | `npm run build` |
| Build output directory | `dist` |

Direct upload is simpler for occasional deploys; Git integration is better if
you push often.
