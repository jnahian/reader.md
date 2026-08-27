# Configurable Focus Dimming — Design

**Date:** 2026-08-28
**Status:** Approved, ready for planning
**Extends:** `2026-08-27-focus-mode-design.md`

Focus mode's dimming ships as a single on/off switch. Two of its hardcoded
values become settings: how wide the lit region is, and how dark everything
else goes. The other hardcoded values (fade duration, the H1–H4 scan, the
100px active-heading threshold, the find/diff/`< 2 headings` suspensions) stay
as they are.

## Region depth

A new `FocusRegionDepth: Int` enum — `any = 4`, `h3 = 3`, `h2 = 2`, `h1 = 1` —
persisted at `reader.md.focus.regionDepth`, defaulting to `any`, which is
today's behaviour exactly.

Depth names the deepest heading level that ends a region. At `h2`, an `h3`
inside a section is not a boundary, so the lit region spans the whole `h2`
section including its subheadings.

In `applyFocusDim` (`bridge.js`) only the boundary list changes:

```js
blocks.forEach((b, i) => {
  const level = +b.tagName[1];
  if (/^H[1-4]$/.test(b.tagName) && level <= depth) headings.push(i);
});
```

Everything downstream is untouched: the ≤100px active scan, the `next` lookup,
the `headings.length < 2` guard, the flat-sibling walk.

### Why this is not the rejected rule

The original spec rejected "region ends at the next heading of the same or
higher level" because it is *relative to the active heading*: with
`h2 A / h3 A.1 / h2 B`, a ~20px scroll flips the active heading between `A.1`
and `A` and swings the lit region between one paragraph and the whole of A.

Depth is an *absolute* level, fixed by the setting and independent of which
heading is active. The lit region changes only when a boundary heading is
crossed, and at depth `h2` the `h3` is not a boundary at all — so the flicker
case cannot arise. The property the original design was chosen for survives.

### Degenerate case

A document whose headings are all deeper than the chosen depth — every heading
an `h3` at depth `h2` — produces an empty boundary list and therefore no
dimming. This is the same answer the existing `< 2 headings` guard already
gives, and it is deliberate rather than special-cased: at that depth the
document genuinely has no regions to distinguish.

### The control

`Picker("Region ends at")` in the Focus Mode section:

| Option | Depth |
| --- | --- |
| Any heading (default) | `any` |
| H3 or above | `h3` |
| H2 or above | `h2` |
| H1 only | `h1` |

### Keep it out of the outline

`applyFocusDim` and `reportActiveHeading` both run a ≤100px "topmost heading
above the fold" scan, and the second drives the outline's active-row
highlight. They stay separate functions. Depth must not reach
`reportActiveHeading`: the outline highlights the heading you are actually
under, at every level, regardless of how wide the lit region is. Folding the
two scans into a shared helper would leak it.

## Dim opacity

`focusDimOpacity: Double` on `AppState`, persisted at
`reader.md.focus.dimOpacity`, default `0.38` — today's value.

Loaded with `defaults.object(forKey:) as? Double ?? 0.38`, the idiom the four
existing focus keys use. `defaults.double(forKey:)` returns `0` for an absent
key, and `0` is a valid-looking opacity that would render invisible text.

The setter clamps to `0.12...0.60`. The value is interpolated into a CSS
custom property, so the clamp is the only thing standing between a bad write
and unreadable or invisible content. `0.60` is the point above which dimming
stops reading as dimming; `0.12` is the point below which a glance back at the
previous section stops being possible — the property the original `.38` was
chosen for.

`template.html`'s rule becomes:

```css
.focus-dim { opacity: var(--focus-dim-opacity, .38); transition: opacity .2s ease; }
```

The fallback keeps the rule correct if the property is ever unset.

### The control

A slider in the Focus Mode section, following the "Text size" row already in
that Form: `LabeledContent` + `Slider` + a `.monospacedDigit()` readout at
`.frame(width: 44, alignment: .trailing)`.

The slider binds to *strength*, not opacity — `get { 1 - opacity }`,
`set { setFocusDimOpacity(1 - $0) }` — so dragging right dims more, which is
the direction the label implies. Range 40%–88% in steps of 2% (opacity
`0.60` to `0.12` in steps of `0.02`), default 62%. The step keeps the readout
from showing a value the slider cannot land on again.

### Both rows disable together

`.disabled(!state.focusDimSections)`. With the dimming switch off the two
controls have nothing to act on, and greying them says so without hiding them.

### The Settings window height

`SettingsView`'s `.frame(minHeight: 680)` rises to fit two more rows. The
`Settings` scene's `NSWindow` autosaves its frame under a fixed key, so a
window last closed before the section grew reopens at the old height and clips
the bottom of the form. This has already produced two fix commits on the focus
mode branch; it is the single most likely thing to ship broken.

## Plumbing

`window.ReaderMd.setFocusDim(on)` widens to `setFocusDim(on, opacity, depth)`.
`depth` crosses the bridge as the enum's raw `Int` (1–4), so the comparison in
`applyFocusDim` is a plain `level <= depth`. It sets `--focus-dim-opacity` on
`:root`, stores `focusDim` and the depth, and calls `applyFocusDim()`.

On the Swift side the coordinator's `lastFocusDim: Bool?` becomes a small
`Equatable` struct holding all three values. Both places that read it need the
widened value:

- `applyFocusDim`'s `guard lastFocusDim != on` early-out — otherwise an
  opacity or depth change with `on` unchanged is silently swallowed.
- the `ready` replay in the message handler, which re-pushes state to a
  freshly loaded web view.

## Preview while adjusting

Dimming renders only while focus mode is running, and the sliders live in a
separate window — so without a preview the slider has no visible effect at the
moment you are dragging it.

`focusDimPreview: Bool` on `AppState`, set on `SettingsView`'s `.onAppear` and
cleared on `.onDisappear`. `focusDimActive` becomes:

```swift
var focusDimActive: Bool { (focusMode || focusDimPreview) && focusDimSections }
```

So the document window behind Settings dims at the current values and updates
as they change, and closing Settings clears it. Focus mode's own state is
untouched throughout — the preview only widens what counts as "dimming is
showing", never what counts as "focus mode is on".

## Testing

`swift test` covers pure logic, so it covers:

- round-trip of both new keys through `Settings`, including the absent-key
  defaults
- opacity clamping at both ends of `0.12...0.60`
- `focusDimActive` under the preview flag: on with `focusDimPreview` alone, off
  when `focusDimSections` is off, unchanged `focusMode` throughout

`FocusModeTests`' `setUp`/`tearDown` save and restore every focus key
deliberately, so tests that flip switches don't leak into each other. Both new
keys are added there, or the suite becomes order-dependent.

The region logic itself is JavaScript inside a `WKWebView` and is not reachable
from `swift test`. It is verified by running the app: a document with nested
headings at each of the four depths, and one whose headings are all deeper than
the chosen depth.

## Documentation

None of this prose is test-guarded — `ShortcutDocTests` only checks that
shortcuts appear in both places, and no shortcut changes here.

- The comment block above `applyFocusDim` in `bridge.js` asserts the region
  ends at the next heading of any level and argues why. **Amended, not
  deleted:** it should explain the depth filter and why an absolute level does
  not reintroduce the flicker the comment argues against.
- `2026-08-27-focus-mode-design.md`, "What 'current' means" — a pointer to this
  document, so the rejected-alternative argument is not read as still describing
  the shipped behaviour.
- `docs/features/reading.md`, the focus mode section's dimming paragraph.
- `Sources/ReaderMd/Resources/docs/CHANGELOG.md`.
- `docs/features/reading.shots.json` — the Settings shot shows the Focus Mode
  section, which gains two rows; re-run the manifest rather than editing the
  image.
