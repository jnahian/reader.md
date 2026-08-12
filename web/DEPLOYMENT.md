# Deployment — Cloudflare Pages

The site is a static Astro build (`dist/`) hosted on Cloudflare Pages, served at
[reader-md.jnahian.me](https://reader-md.jnahian.me) (the `site` value in `astro.config.mjs`).

## Deploys are automatic — on `main`, when `web/` changes

The GitHub repo is connected to the Pages project, so **Cloudflare rebuilds and
publishes when a push to `main` touches `web/`** — that push is the deploy,
nothing to run by hand. A commit that changes only Swift sources, `docs/`, or
the README builds nothing.

Because the site lives in a subdirectory (**Pages → reader-md-web → Settings →
Build**):

| Setting | Value | Why |
|---|---|---|
| Root directory | `web` | the site isn't at the repo root |
| Build command | `npm run build` | |
| Build output directory | `dist` | |
| Build watch paths — include | `web/*` **and `docs/*`** | app-only commits don't rebuild the site |
| Build watch paths — exclude | *(empty)* | |
| Preview deployments | None | `main` is the only branch that deploys |

> **`docs/*` is required, not optional.** Every page under `/docs/` is built from
> `docs/*.md`, `docs/features/*.md`, and `docs/assets/screenshots/` — all outside
> `web/`. With only `web/*` watched, editing any documentation page or re-shooting
> a screenshot — the routine change this setup exists for — changes nothing under
> `web/`, so Cloudflare **skips the build** and the live site stays stale with no
> error anywhere. Add `docs/*` to the include list in the Pages project.

Watch paths are matched against repo-root-relative paths, so the prefix is
`web/`, not `src/` — even though **Root directory** is `web`. A wildcard `*`
spans `/`, so `web/*` covers `web/src/data/changelog.ts`; there is no `**` form.

These live in the Pages project, not in this repo, so nothing here will tell you
they changed. They are also settable through the API — `path_includes`,
`path_excludes`, and `preview_deployment_setting` under `source.config` of
`PATCH /accounts/{id}/pages/projects/reader-md-web`. PATCH the whole
`source.config` object; sending a partial one drops the sibling keys.

**Preview deployments are off**, so a PR touching `web/` gets no preview URL.
To bring them back for specific branches, set `preview_deployment_setting` to
`custom` and list them in `preview_branch_includes`.

### When it builds anyway

Watch paths are skipped — and the build runs regardless of what changed — when a
push carries **0 changed files, 3,000+ changed files, or 20+ commits**. A big
merge or a force-push can therefore deploy on its own; that's Cloudflare working
as documented, not the setting being broken.

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
