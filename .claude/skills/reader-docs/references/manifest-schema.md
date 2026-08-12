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
| `page` | yes | Must match `docs/features/<page>.md`; also the asset directory name |
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
