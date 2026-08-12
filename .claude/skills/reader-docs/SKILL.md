---
name: reader-docs
description: Write a Reader.md feature documentation page with real screenshots captured from the running app. Use whenever the user wants to document a feature, write or refresh a docs page, re-shoot screenshots after a UI change, or mentions the docs site's feature pages — even if they don't say "documentation" explicitly.
---

# reader-docs

Produce one documentation page: prose in `docs/features/<slug>.md`, assets in
`docs/assets/screenshots/<slug>/`, captured deterministically from a manifest.
The Astro site renders `docs/features/` directly, so the markdown is the only
copy of the prose — never write page content into `web/src/`.

**The three gates are hard requirements. None may be auto-approved.**

| # | When | What the user approves |
|---|------|------------------------|
| 1 | Before capture | The manifest: shot list, states, actions |
| 2 | Before commit | The finished page and every asset |
| 3 | Before push | That publishing is intended |

**Gate 3 matters more here than it looks.** Cloudflare Pages builds and
publishes on any push to `main` that touches `web/`. There is no staging step —
merging *is* publishing.

## 1. Scope the page

Read `docs/features.md` for the canonical feature list and decide which features
this page covers. If a shortcut is involved, verify it against the
`.keyboardShortcut` bindings in `Sources/ReaderMd/ReaderMdApp.swift`. That file
is the authority — the README and the site have both carried wrong shortcuts.

Two caveats when checking shortcuts there:

- Not every shortcut is a `.keyboardShortcut`. ⌘W is wired through
  `AppDelegate`'s key monitor, and ⌘, comes free with SwiftUI's `Settings`
  scene. A shortcut missing from that grep is not necessarily absent from the
  app.
- The bundled `Sources/ReaderMd/Resources/docs/SHORTCUTS.md` ships to users and
  is the second authority. If it and `docs/features.md` disagree, something is
  wrong — stop and reconcile before writing.

## 2. Author the manifest — gate 1

Write `docs/features/<slug>.shots.json` per `references/manifest-schema.md`.

- Shot ids ordered and zero-padded (`01-…`), one per meaningful state.
- Prefer stills. Add a `video` shot only when the feature IS a motion —
  filtering as you type, live reload, zoom and pan. A state is a still.
- Reach states with keystrokes and `reader` CLI calls. Anything that needs
  right-click, drag, or a sheet is a manual shot (`"manual": true`) — see
  `references/manual-shots.md`.
- Never point `prefs` at a real folder. Fixture paths only, via `<fixtures>`.

**Gate 1:** present the shot list, the state each shot shows, and every action.
Iterate until approved. Do not capture before approval.

## 3. Capture

```
.claude/skills/reader-docs/scripts/capture.sh docs/features/<slug>.shots.json
```

Re-shoot one shot with `--only <shot-id>`. Check reproducibility with
`--verify-repro`, which captures a fresh set and compares it to the committed
one by SSIM.

The run drives its **own** app build at `build/shots/Reader.md.app`
(bundle id `com.nahian.reader-md.shots`), builds it if absent, and hides your
other applications for the duration — Liquid Glass samples whatever is behind
the window, so a terminal back there bleeds into the sidebar and makes two runs
disagree. Your apps are unhidden again on exit, including on failure.

**Quit your normal Reader.md first.** Both builds are called "Reader.md" and
AppleScript cannot tell them apart; the harness refuses to run rather than risk
driving the real one.

Exit codes: `3` missing tool or permission (the message says which), `4` an
isolation guard tripped — pointed at the real preference domain, the app bundle
has the wrong id, or the wrong app is running, `5` app never appeared, `6`
focus kept being stolen, `7` a shot never settled, `8` the window would not
hold its size, `9` not reproducible between runs.

Then **look at every image**. Anything showing a real path, a real filename, or
a real file count is a failed capture, not a cosmetic issue — re-shoot it.
Watch every clip end to end: no cursor in frame, no tooltip, motion legible,
and the keystroke badge on the right frame.

## 4. Write

Four steps, in order:

1. **Read the product context.** If `.agents/product-marketing.md` exists, read
   it first — it carries who the reader is and the words they actually use, so
   every page describes the same product to the same person. If it is missing,
   say so once ("pages will lack shared audience grounding — the
   `vendored/product-marketing` skill creates it") and carry on. Do not stop to
   create it mid-page.
2. **Draft** against `references/page-template.md`.
3. **Apply `references/voice.md`.**
4. **Polish with `vendored/copy-editing`**, invoked explicitly. Use its
   focused-pass method and `references/plain-english-alternatives.md`.

**`voice.md` wins, always.** The vendored skills are marketing skills: they
speak of conversion, benefits, and driving action. That framing suits a landing
page and is wrong here. Take their *mechanics* — plain English, one idea per
sentence, cutting hedges and filler — and ignore any pull toward
feature-marketing adjectives, benefit-led restructuring, or a call to action.
A feature doc's job is to be accurate and quick to scan, not to sell.

If a vendored directory has no `SKILL.md` (not yet vendored — see
`vendored/VERSIONS.md`), note it once and write with the page template and
voice rules alone.

Reference assets by true relative path so the page also reads correctly in
Reader.md itself:

```markdown
![The outline pane, opened with ⇧⌘B](../assets/screenshots/reading/01-outline.png)
```

Every clip needs prose describing what it shows. A `.mp4` degrades to a broken
image in Reader.md and on GitHub, so a reader who cannot play it must lose
nothing.

## 5. Review — gate 2

Present the page and its assets. Iterate until approved. Nothing is committed
before approval.

## 6. Publish — gate 3

Verify the site builds, then ask before pushing:

```
cd web && npm run build
```

Then check that the push will actually deploy:

```
git diff --name-only origin/main...HEAD | grep -q '^web/' && echo "will deploy" || echo "WILL NOT DEPLOY"
```

Cloudflare's build watch paths decide whether a push rebuilds the site. If they
are still `web/*` only, a commit touching just `docs/` — re-shot screenshots, a
prose fix — changes nothing under `web/`, the build is skipped, and the live
site stays stale **with no error anywhere**. Adding a new page usually also
edits `web/src/pages/docs.astro` to link it, which masks this; updating an
existing page does not.

If the check says `WILL NOT DEPLOY`, say so at the gate and give the fix: add
`docs/*` to the include list (Pages → reader-md-web → Settings → Build), per
`web/DEPLOYMENT.md`. Do not work around it by touching a file under `web/`.

**Gate 3:** state plainly that pushing to `main` publishes the page live, and
require an explicit yes.

## Vendored skills

`vendored/` holds two skills from
[coreyhaines31/marketingskills](https://github.com/coreyhaines31/marketingskills)
(MIT), pinned to a commit by `scripts/vendor-skills.sh`:

| Skill | Role |
|---|---|
| `product-marketing` | Creates `.agents/product-marketing.md` — audience, positioning, customer vocabulary. Run it **once per project**, not per page. It writes no page content |
| `copy-editing` | The polish pass in step 4 |

Re-vendor with `./scripts/vendor-skills.sh` (latest) or with a commit SHA. See
`vendored/VERSIONS.md` for why the other three upstream writing skills are
deliberately not vendored.

## Output contract

```
docs/features/<slug>.md              # prose — the only copy
docs/features/<slug>.shots.json      # manifest — reproducibility
docs/assets/screenshots/<slug>/      # stills, clips, posters
```

Re-running the manifest after a UI change regenerates every asset. Never
hand-shoot an image into the final page unless the manifest marks it `manual`.
