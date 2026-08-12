# Feature documentation with real screenshots

Document every Reader.md feature as a set of web-published pages, each carrying
real screenshots captured from the running app. The screenshots are produced by
a committed, reusable harness — not shot by hand — so that a UI change is
answered by re-running a command rather than by re-shooting thirty images.

The deliverable of this spec is **the machinery plus one finished page**. The
remaining nine pages are repetition under a proven pipeline and belong to a
follow-up plan.

## Why this shape

Two constraints drive the design.

**The screenshots must be reproducible.** Reader.md ships often — the Sparkle
auto-updater means users see the newest UI within a day of release. Hand-shot
documentation drifts from the app within two releases and then actively misleads.
A harness that regenerates the whole set from a manifest keeps the docs honest
at the cost of one command.

**The prose must have exactly one home.** `web/CLAUDE.md` states that nothing in
`src/data/` is a source of truth, and the root `CLAUDE.md` orders documentation
bundled docs → `docs/` → site. Per-feature prose is new content, so it goes in
`docs/` and the site renders it directly. Mirroring ten pages of prose into
typed TypeScript strings by hand would reintroduce the drift the convention
exists to prevent.

## Prior art

The design deliberately mirrors the `shopify-apps-doc-writer` skill already
installed on this machine, which solves the same problem for a web app. Its
manifest → capture → write → gate structure translates field for field, with
AppKit driving in place of Playwright:

| shopify-apps-doc-writer | reader-docs |
|---|---|
| `path: /admin/…` | `prefs:` seed + `reader <fixture.md>` |
| `actions: [click "[data-testid=…]"]` | `actions: [{key:"b",mods:["command"]}]` |
| `waitFor: <selector>` | settle loop — no selectors exist |
| `crop: iframe \| full-admin` | `screencapture -l <winid> -o`, window only |
| `capture.js` (Playwright) | `capture.sh` + `winid.swift` |
| gate 3 = external publish | gate 3 = push to `main` (Cloudflare auto-deploys) |

## Proven mechanics

Every mechanism below was verified end to end on macOS 26.6.1 before this spec
was written. None of it is assumed.

- **Window capture.** `CGWindowListCopyWindowInfo` yields the app's window id
  without an interactive picker; `screencapture -l <id> -o -x` writes a retina
  PNG with no shadow and no permission prompt. Verified: a 1400×900 window
  captured at exactly 2800×1800.
- **Keystroke driving.** `osascript` System Events `keystroke` changes app state.
  Verified by capturing before and after ⌘B and confirming the images differ.
- **Geometry control.** `set size` / `set position` on the window via System
  Events produces identical frames run to run.
- **Settling.** Opening a Mermaid- and KaTeX-heavy document and capturing
  immediately required two settle polls before consecutive frames matched; the
  resulting image had every diagram and equation fully laid out. A fixed `sleep`
  would have captured mid-render.
- **CLI driving.** `reader <file.md>` opens a document in the running app, so
  document state is reachable without synthesising an Open dialog. Note the verb
  form: there is no `reader open` subcommand.

Two hazards surfaced during verification and are designed against below:

- **Focus drift.** Slack took focus partway through a scripted run. Any
  subsequent keystroke would have gone to Slack rather than Reader.md.
- **Private data.** A capture taken against the real preferences domain showed
  client project names, private design-document filenames, and a personal file
  count. That image could not have been published.

## Prerequisites

The harness requires Screen Recording (for `screencapture` and window titles)
and Accessibility (for System Events) permissions on the terminal that runs it.
Both were already granted on this machine. `capture.sh` checks for them and
fails with an actionable message rather than producing black or empty images.

## Part 1 — Feature inventory

`docs/features.md` is currently wrong, and the feature list is the input to
everything else. Two bullets appear twice, and neither pair is a clean
older/newer split — each copy carries a detail the other lacks:

- **Git-aware** ×2 — one says "scope menu"; the other says "scope popover beside
  it" and adds "with a filter field for repos with many branches".
- **Context menus** ×2 — one includes "Add to Favorites"; the other omits it.

Merge each pair into a single bullet carrying the union of the details, then
verify every bullet against the `.keyboardShortcut` bindings in
`ReaderMdApp.swift` and against the running app. The root `CLAUDE.md` already
names those bindings as the authority over both the README and the site.

Output: the canonical feature list, and a mapping from each feature to the page
that will document it.

## Part 2 — Fixtures

Screenshots are taken against a fixture corpus, never the user's real folders.
This is what keeps captures reproducible and free of private data.

The corpus is **generated into a temp directory, not committed**. `FileScanner`
scans each root recursively for markdown, so a fixture library committed
anywhere in this repo would show up in the sidebar alongside the real
documentation for anyone who adds the repo as a root — including inside the
screenshots, where `docs/features/*.md` and fake handbook files would
intermingle. Generating it sidesteps that entirely and keeps the fixtures out
of git.

`fixtures.sh` (all scripts live in the skill directory — see part 4) builds two
things:

- A **markdown library** — a handbook-shaped folder tree with enough files to
  make the sidebar look real, plus documents that exercise specific features:
  one Mermaid/KaTeX document, one frontmatter document, one code-heavy
  document, one long document with deep headings for the outline. The script
  writes the content, so it is byte-for-byte reproducible on every run.
- A **git repository**, built from those files with a commit history and a
  branch, plus staged, unstaged, and untracked markdown so the sidebar badges
  (`M` · `A` · `?` · `U`) and the diff view have real state to show. Commit
  dates are pinned via `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` — without
  this, diff and badge screenshots change on every sweep, producing image churn
  that reflects nothing but the clock.

Fixture root folders are named neutrally (a "Field Notes"-style handbook), so
the sidebar breadcrumbs in a screenshot reveal nothing about the machine. The
temp location is stable within a run and referred to as `<fixtures>` in
manifests.

## Part 3 — The capture harness

`capture.sh` reads a manifest and produces the screenshots for one page. Its
contract is five hard guarantees, each earned from a hazard observed during
verification.

**1. Isolation.** The harness drives a separate app bundle built with
`BUNDLE_ID=com.nahian.reader-md.shots`, which therefore reads its own
`UserDefaults` domain and cannot see or overwrite the real app's folders. The
app's preference keys are namespaced `reader.md.*` under
`com.nahian.reader-md`, so the split is total. `capture.sh` **refuses to run**
against the default domain.

`make-app.sh` currently hardcodes `BUNDLE_ID="com.nahian.reader-md"` on line 8;
this becomes `BUNDLE_ID="${BUNDLE_ID:-com.nahian.reader-md}"`. That one-line
change is unverified — it also feeds the `SUFeedURL`/Sparkle wiring and the
ad-hoc signing step in that script. The implementation plan must verify a
shots-build launches and reads its own domain **before** anything depends on it.
**Stated fallback if it does not come out clean:** `defaults export` the real
domain before a run and `defaults import` it after, with `killall cfprefsd`
around both. The fallback is strictly worse (it mutates and restores real
preferences rather than never touching them) but it unblocks the plan.

**2. Geometry assert.** Each shot sets the window frame from the manifest, then
asserts the captured pixel dimensions equal twice the logical size. A mismatch
fails the run. Without this, a differently-sized image lands silently in `docs/`
and the page layout jitters between screenshots.

**3. Settle, not sleep.** Capture, wait, recapture, compare; repeat until two
consecutive captures are byte-identical, then keep the second. A shot that never
settles within the poll budget fails the run rather than landing a half-rendered
image. Verified to correctly wait out a Mermaid/KaTeX render.

The loop has one edge that must be closed: it terminates on any two identical
consecutive frames, so a state that has not *started* changing yet reads as
already settled. A short mandatory delay before the first capture of each shot
closes it, converting a silent early exit into a correct wait.

**4. Focus assert.** Before every keystroke, verify Reader.md is the frontmost
process; abort the run otherwise. This is a safety requirement, not a
robustness nicety: during verification another application took focus mid-run,
and unguarded ⌘-keystrokes would have been delivered to it.

**5. Post-processing.** Captures are downscaled to 2400px wide via `sips` and
losslessly optimised, then written to
`docs/assets/screenshots/<page>/<id>.png`. Budget: one theme (light) throughout,
except on the appearance page where dark mode is the subject. Roughly 250KB per
image, ~8MB for a full set of about 35 — against a 19MB repository today. PNGs
do not delta-compress, so each full re-sweep adds its full size to history
again; that cost is accepted deliberately in exchange for reproducibility.

`winid.swift` is the supporting helper that resolves the app's window id from
`CGWindowListCopyWindowInfo`.

### Manifest schema

One manifest per page, committed beside it as
`docs/features/<slug>.shots.json`:

```json
{
  "page": "reading",
  "window": { "width": 1400, "height": 900 },
  "prefs": {
    "reader.md.theme": "light",
    "reader.md.showTOC": true,
    "reader.md.folders": ["<fixtures>/field-notes"]
  },
  "shots": [
    {
      "id": "01-outline",
      "open": "field-notes/architecture-overview.md",
      "actions": [{ "key": "b", "mods": ["shift", "command"] }],
      "caption": "The outline pane, opened with ⇧⌘B"
    }
  ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `page` | yes | Must match the containing `docs/features/<slug>.md` |
| `window` | no | Logical window size; default 1400×900 |
| `prefs` | no | Seed values written to the shots preference domain before launch |
| `shots` | yes | Ordered array |
| `shots[].id` | yes | Zero-padded and ordered; becomes the filename |
| `shots[].open` | no | Fixture-relative path opened via the `reader` CLI |
| `shots[].actions` | no | Keystrokes and CLI calls to reach the state; default `[]` |
| `shots[].caption` | yes | Alt text and caption in the page |

Actions are limited to keystrokes, `reader` CLI invocations, and an explicit
`waitMs` escape hatch (discouraged — the settle loop is the default and the
escape hatch exists only for states that settle to a genuinely animating frame).
No action may mutate anything outside the fixture corpus.

### Manual shots

A short list of states cannot be driven cleanly by keystroke and are shot by
hand against the same fixture corpus and window geometry: drag-and-drop onto the
content pane, right-click context menus, the Add Remote SSH sheet, and Finder's
"Open With". These are recorded in the skill's reference material as a checklist
with the exact fixture state each one starts from, so a re-shoot is mechanical
rather than a rediscovery. `capture.sh` never overwrites a manually captured
file; the manifest marks those shots `"manual": true` and the harness skips
them, warning if the file is missing.

## Part 4 — The skill

The skill is the reusable engine and the primary deliverable. It lives at
`.claude/skills/reader-docs/` — project-scoped and committed, because every path
it touches is repo-relative. A user-level skill would put the instructions
outside the repository holding the fixtures and harness they drive, and the two
would drift.

```
.claude/skills/reader-docs/
├── SKILL.md                    # orchestrator and the three gates
├── references/
│   ├── manifest-schema.md
│   ├── page-template.md
│   ├── manual-shots.md
│   └── voice.md
└── scripts/
    ├── capture.sh
    ├── winid.swift
    └── fixtures.sh
```

`SKILL.md` drives one page at a time through: read the feature list for this
page → author the manifest → **gate 1** → capture → write the prose → **gate 2**
→ commit and push → **gate 3**.

The three gates are hard requirements, and none may be auto-approved:

| Gate | When | What is approved |
|---|---|---|
| 1 | Before capture | The manifest: shot list, states, actions |
| 2 | Before commit | The finished page and its screenshots |
| 3 | Before push | That publishing is intended |

Gate 3 deserves emphasis: Cloudflare Pages builds and publishes on any push to
`main` that touches `web/`. There is no staging step and no separate deploy, so
**merging is publishing**. The skill must state this and must never combine
drafting and pushing in one step.

`references/voice.md` captures the tone of the existing documentation rather
than inventing one: direct, second person, features named exactly as they appear
in the UI, and shortcuts always written parenthesised after the label — "Toggle
outline (⇧⌘B)" — matching the convention already used throughout the app and
docs.

## Part 5 — Content model

Ten pages, one per feature area:

| Route | Covers |
|---|---|
| `/docs` | Overview, install, index of the pages below |
| `/docs/library` | Roots, remote folders, cloned repositories |
| `/docs/navigating` | Quick open, file filter, history, favorites, recents |
| `/docs/reading` | Outline, find in page, typography, canvas width, progress |
| `/docs/rendering` | Mermaid, KaTeX, code highlighting, images, frontmatter |
| `/docs/git` | Badges, diff mode, scope menu |
| `/docs/exporting` | PDF export, external editor handoff |
| `/docs/settings` | Appearance, preferences, auto-update |
| `/docs/cli` | `reader` command reference |
| `/docs/shortcuts` | Full key map |

On disk:

```
docs/
├── features.md                       # reduced to an index linking to the pages
├── features/
│   ├── reading.md                    # frontmatter: title, order, summary
│   ├── reading.shots.json
│   └── …
└── assets/screenshots/
    └── reading/01-outline.png
```

Pages reference images by true relative path
(`../assets/screenshots/reading/01-outline.png`). That path is correct on disk,
so the pages render correctly in three places with no rewriting: in Reader.md
itself, on GitHub, and — after one build-time rewrite — on the site.

`docs/features.md` is reduced to an index. It keeps working as the entry point
the README and the app's own docs link to, and it remains the human-readable
list of everything the app does.

## Part 6 — Site plumbing

Astro 7, no content collections in the project today. Four pieces:

1. **`web/src/content.config.ts`** — a `docs` collection loaded with
   `glob({ pattern: "*.md", base: "../docs/features" })`. Frontmatter is schema
   -checked, so a malformed page fails `npm run build` rather than rendering
   wrong — the same guarantee the typed `content.ts` gives today. Astro's
   Content Layer reads the files at build time through Node's filesystem, so
   the out-of-root base is not a problem for builds; `astro dev` additionally
   needs `vite.server.fs.allow: [".."]`.
2. **`web/src/pages/docs/[...slug].astro`** — one static route per page via
   `getStaticPaths`. `/docs` remains a hand-written page: overview, install, and
   an index of the ten.
3. **A remark plugin** rewriting `../assets/screenshots/…` to `/screenshots/…`
   at build time. This single piece of glue is what buys three-way-correct image
   paths.
4. **A `prebuild` npm script** copying `docs/assets/screenshots/` to
   `web/public/screenshots/`, which is gitignored. A committed symlink would
   avoid the build step entirely; it is rejected because symlinked directories
   are less portable through the Cloudflare Pages build than a copy.

`DocsSidebar.astro` gains a second level: a page list sourced from the
collection and ordered by frontmatter, above the existing in-page scrollspy,
which now takes its headings from `render()` rather than the hardcoded
`docsToc` array.

Images render at 1200px CSS width from 2400px files, giving 2× on retina, with
`loading="lazy"`, explicit `width`/`height` to prevent layout shift, and a
caption beneath.

**Migration:** `content.ts` currently links to `/docs#shortcuts`; those anchors
become `/docs/shortcuts`. Internal links are updated as part of this work.
Inbound external links to old anchors still land on `/docs`, which remains a
real page.

## Scope

**In scope:** parts 1 through 6, and one finished page — `/docs/reading`.

`reading` is the pilot because it is structurally representative of seven of the
ten pages: about six shots, entirely keyboard-driven, exercising preference
seeding, geometry, keystrokes, and the settle loop. `git` is the hardest page,
but piloting on the outlier risks fitting the skill to it. The fixture git
repository is still built in part 2, so `git` is unblocked later.

**Explicitly deferred to a follow-up plan:** the remaining nine pages.

**Out of scope:** video or animated capture; localisation; documenting anything
that is not a shipped feature; any change to the app itself beyond the one-line
`BUNDLE_ID` default in `make-app.sh`.

## Review checkpoint

After the pilot page is written and captured, the user reviews it, and the
corrections are folded back into `SKILL.md` and its references — not just into
the page. The point of the pilot is to find the skill's gaps while the cost of
fixing them is one page rather than ten. The follow-up plan for the remaining
nine pages should not begin until the skill has absorbed that feedback.

## Verification

- `swift build` still succeeds after the `make-app.sh` change, and
  `./make-app.sh` produces a launchable app with the unchanged default bundle id.
- A shots-build launches under `com.nahian.reader-md.shots` and does not read
  the real domain's folders — checked by confirming its sidebar shows only
  fixture roots.
- `capture.sh` run twice in a row produces **visually** identical images for
  every shot: dimensions equal, and pixel difference under a small threshold
  (`compare -metric AE`). This is the reproducibility contract. Byte-equality is
  deliberately *not* the criterion here — Liquid Glass and vibrancy materials
  sample what is behind the window, and PNG encoding is not contractually
  stable, so exact-bytes would fail falsely across runs. Byte-equality is used
  only inside the settle loop, where the question is merely "did anything
  change" between two captures moments apart.
- `capture.sh` aborts with a clear message when the app is not frontmost, when
  the geometry assert fails, and when pointed at the real preference domain.
- No screenshot contains a path, filename, or count originating outside the
  fixture corpus. Checked by eye against every captured image at gate 2.
- `cd web && npm run build` succeeds, and `/docs/reading` renders with all
  screenshots resolving.
- The pilot page's prose matches the app: every shortcut it names is checked
  against the `.keyboardShortcut` bindings in `ReaderMdApp.swift`.
