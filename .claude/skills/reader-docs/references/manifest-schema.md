# Shot Manifest Schema

Lives at `docs/features/<slug>.shots.json`, committed beside the page it feeds.
`scripts/capture.sh` executes it.

## Top level

```json
{
  "page": "reading",
  "window": { "width": 1400, "height": 900 },
  "prefs": { "reader.md.folders": ["<fixtures>/field-notes"] },
  "shots": [ ... ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `page` | yes | The asset directory name. For a feature page it must match `docs/features/<page>.md`; `hero` is the one manifest with no page — it feeds the README and the landing-page hero |
| `window` | no | Logical window size, default 1400×900. Captured at 2× |
| `domain` | no | Preference domain; defaults to `com.nahian.reader-md.shots`. Setting it to the real domain is refused |
| `prefs` | no | Seeded before launch. `<fixtures>` expands to the generated corpus root |
| `shots` | yes | Ordered array |

## Shot

```json
{
  "id": "03-outline",
  "open": "field-notes/guides/setup.md",
  "actions": [ { "key": "b", "mods": ["shift", "command"] } ],
  "caption": "The outline pane, opened with ⇧⌘B"
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Zero-padded and ordered; becomes the filename |
| `open` | no | Fixture-relative path opened via the `reader` CLI |
| `prefs` | no | Merged over the manifest's before this shot launches — one light shot on an otherwise dark page |
| `actions` | no | Run in order after `open`; default `[]` |
| `caption` | yes | Alt text and caption |
| `video` | no | `{ "seconds": n }` — records a clip instead of a still |
| `manual` | no | Captured by hand; the harness skips it and warns if the file is absent |

## Actions

| Action | Shape |
|---|---|
| keystroke | `{ "key": "b", "mods": ["shift", "command"] }` |
| open a file | `{ "reader": "field-notes/guides/setup.md" }` |
| wait | `{ "waitMs": 1200 }` |
| edit a fixture | `{ "appendTo": "field-notes/index.md", "text": "\n## New\n" }` |
| click | `{ "click": [1092, 26] }` |
| right-click | `{ "rclick": [108, 268] }` |
| drag | `{ "drag": [190, 213, 410, 213] }` |

Pointer coordinates are **window points**, not screen points and not pixels of a
captured image: the harness adds the window's origin itself, so a shot survives
the window moving and the numbers read as a position in the UI. Measuring one
off a committed 2400px capture means dividing by 2400/1400 ≈ 1.714, *not* 2.

A pointer action earns no keystroke badge — nothing was pressed. Prefer a
keystroke whenever one exists; a coordinate is the most fragile thing a manifest
can hold, and it is worth it only for a state with no keyboard route at all (the
markup popover needs a real drag; a context menu needs a right-click).

`appendTo` exists for live reload, where the disk acts and the keyboard does
not. It is the one action that writes, so the path must stay inside the fixture
corpus — a leading `/` or a `..` aborts the run. It earns no keystroke badge:
nothing was pressed.

`mods` are `command`, `shift`, `option`, `control`. Keys are single characters
as typed; the harness escapes them for AppleScript, so `"\\"` (a literal
backslash, for ⇧⌘\) is fine.

**`waitMs` means opposite things for stills and clips.** For a still it is a
discouraged escape hatch — the settle loop is the default, and it exists only
for a state that settles to a genuinely animating frame. For a clip it *is* the
choreography, since no settle loop is possible, and the values are what make the
motion readable.

## Shots are independent

Every shot starts from a freshly launched app with the manifest's `prefs`
re-seeded — state does **not** carry from one shot to the next. Write each
shot's `actions` as though nothing has happened yet: if a shot needs the outline
open, it toggles the outline itself, even if the shot before it already did.

This is why the harness relaunches between shots, and it is worth the seconds
it costs. When shots did carry state, opening the outline for one shot left it
open in the next, and a find bar full of highlighted matches turned the
following typography shot into a second find shot. It also keeps `--only`
honest: re-shooting one shot reproduces the committed image rather than
whatever the preceding shots happened to leave behind.

## A known `--verify-repro` failure

Any shot with the Quick Open palette in it fails the SSIM check — measured at
0.967 for `library/04-headings`, and `library/03-commands` has the same shape.
The two runs are identical in content; the palette sits about 3px lower in one
of them. Its result list is a `LazyVStack` inside a `maxHeight` frame, so the
height SwiftUI measures depends on how many rows were realised when layout
settled, and the palette is centred, so a fractional difference moves it.

Treat that one failure as known. A palette shot differing by *content* — a
different query, a different result order — is a real regression.

`annotations/04-thread` is machine-dependent for a different reason: a comment's
author is `NSFullUserName()`, which the app takes from macOS and no preference
overrides. The committed shot carries the maintainer's name, deliberately.
Re-shooting it elsewhere will put a different name in the thread — expected, not
a leak, but worth noticing before committing the result.

## Keystroke badges

In a video shot, every keystroke automatically gets a badge burned into the
clip — a large light pill showing the shortcut in Apple's glyph order (⌃⌥⇧⌘),
timed to the frame the key actually fired. Nothing in the manifest turns this
on; it follows from the `key` actions. Choreograph `waitMs` so badges do not
overlap: ~1.5s between keystrokes reads comfortably, since a badge lingers
1.4s.

## Preference keys

Seedable keys, from `Sources/ReaderMd/Models/Settings.swift`:

| Key | Type | Values |
|---|---|---|
| `reader.md.folders` | array of paths | Use `<fixtures>/…` |
| `reader.md.theme` | string | `light`, `dark`, `system` |
| `reader.md.contentWidth` | string | `narrow`, `wide`, `full` |
| `reader.md.showSidebar` | bool | |
| `reader.md.showTOC` | bool | |
| `reader.md.fontScale` | number | `1.0` is default |
| `reader.md.readingTheme` | string | see `ReadingTheme` |
| `reader.md.diffMode` | bool | |

The harness always seeds `lastSeenBuild` itself. Without it a fresh domain
looks like a first launch after an update and the app opens its What's New
changelog over the content pane — which is what the first fixture capture
photographed.

## Rules

- Never reference a path outside the fixture corpus.
- One theme (dark) everywhere except the appearance page, where light is the
  contrast case. The site is dark-only, so light shots glare.
- Five clips total across all ten pages. A state is a still.
