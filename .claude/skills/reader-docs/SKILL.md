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

Follow `references/page-template.md` for structure and `references/voice.md`
for tone. Reference assets by true relative path so the page also reads
correctly in Reader.md itself:

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

**Gate 3:** state plainly that pushing to `main` publishes the page live, and
require an explicit yes.

## Output contract

```
docs/features/<slug>.md              # prose — the only copy
docs/features/<slug>.shots.json      # manifest — reproducibility
docs/assets/screenshots/<slug>/      # stills, clips, posters
```

Re-running the manifest after a UI change regenerates every asset. Never
hand-shoot an image into the final page unless the manifest marks it `manual`.
