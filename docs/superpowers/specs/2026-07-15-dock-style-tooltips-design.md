# Dock-Style Tooltips — Design

**Date:** 2026-07-15
**Status:** Superseded — the glass-view approach below was dropped during implementation. The shipped tooltip is a hand-drawn pill + pointer in a plain `NSView` (no `NSGlassEffectView`/`NSVisualEffectView`); see `Sources/ReaderMd/Views/DockTooltip.swift`.

## Goal

Replace the standard macOS yellow tooltip (SwiftUI `.help()`, backed by
`NSToolTip`) with a rounded, glass/material bubble that visually matches the
app's Liquid Glass chrome. Applied to every hoverable control that currently
uses `.help()`.

**Motivation:** aesthetic only — the system tooltip clashes with the Liquid
Glass toolbar/sidebar. No functional change to *what* the tooltips say.

## Why a custom implementation is required

macOS exposes no API to restyle `.help()`. Achieving the Dock look means
building a small custom hover→floating-bubble system.

Most `.help()` call sites live on the **native window toolbar**
(`Toolbar.swift`). A tooltip for a toolbar button must float *outside* the
SwiftUI content hierarchy. This rules out the cheap options:

- **SwiftUI `.overlay`** — clipped by parent/toolbar bounds. ✗
- **Shared overlay in `ContentView`** — `ContentView` sits below the native
  toolbar; can't cover toolbar buttons. ✗
- **`.popover`** — floats, but hover-driven popovers feel wrong (zoom
  animation, focus stealing, dismisses sibling popovers). ✗
- **One shared borderless `NSPanel`** — floats above everything including the
  toolbar, no clipping, uniform for every call site. ✓ **Chosen.**

## Architecture

Three pieces, one new file (`Sources/ReaderMd/Views/DockTooltip.swift`) plus
call-site swaps.

### 1. `TooltipController` (singleton)

Owns a **single reused** borderless, non-activating `NSPanel`.

- Panel: `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`,
  `isFloatingPanel = true`, `level = .popUpMenu` (above toolbar/content),
  `hasShadow = true`, `backgroundColor = .clear`, `isOpaque = false`,
  `ignoresMouseEvents = true` (tooltip never intercepts clicks).
- Content view (built once, text updated per show) — Liquid Glass with a
  pre-26 fallback, mirroring `GlassPanel` but in AppKit since the panel
  content is not SwiftUI:
  - **macOS 26+:** `NSGlassEffectView` with `cornerRadius = 8`; the
    `NSTextField` label is its `contentView`.
  - **macOS 13–15:** `NSVisualEffectView`, `material = .toolTip`,
    `blendingMode = .behindWindow`, layer-backed with `cornerRadius = 8` and
    full corner mask; the label is added as a subview.
  - Wrapped behind an availability guard (`if #available(macOS 26.0, *)`),
    the same pattern `GlassPanel` uses. Deployment target stays macOS 13.
  - `NSTextField` label in both cases: non-editable, non-bezeled, clear
    background, inset ~10pt horizontal / ~5pt vertical.
- API:
  - `show(text:, anchorScreenFrame:)` — set text, size to fit, position, fade
    the panel in (`NSAnimationContext`, ~0.1s).
  - `hide()` — fade out and order out.
- **Positioning:** horizontally center the panel on `anchorScreenFrame`,
  clamp x to the visible screen. Default place the bubble a few pt **below**
  the anchor (correct for top-of-window toolbar buttons). If the bubble's
  bottom would fall below the screen's visible frame, flip to **above** the
  anchor. That is the complete edge-avoidance logic.

### 2. `TooltipTracker` (`NSViewRepresentable`)

A zero-size background view added by the modifier. Its `NSView` installs an
`NSTrackingArea` (`.mouseEnteredAndExited`, `.activeInKeyWindow`,
`.inVisibleRect`).

- `mouseEntered` → start a ~0.4s delay timer. On fire, compute the host
  control's screen frame via
  `window.convertToScreen(convert(bounds, to: nil))` and call
  `TooltipController.shared.show(text:anchorScreenFrame:)`.
- `mouseExited` → cancel the timer and call `TooltipController.shared.hide()`.

`NSTrackingArea` is used instead of SwiftUI `.onHover` for reliable
enter/exit (including during scroll) and exact AppKit screen coordinates.

The tracked frame is the tracker view's own bounds, which fills the modified
control via `.background`, so it matches the control's frame.

### 3. `.dockTooltip(_:)` view modifier

```swift
extension View {
    func dockTooltip(_ text: String) -> some View {
        self
            .background(TooltipTracker(text: text))
            .accessibilityLabel(text)
    }
}
```

`.accessibilityLabel(text)` preserves the VoiceOver hint that `.help()` used
to provide — **required**, not optional.

## Call-site changes

Mechanical swap of `.help("…")` → `.dockTooltip("…")` at every current site
(dynamic-string sites keep their expression):

- `Views/Toolbar.swift` — 8 sites (sidebar, back, forward, outline, reload,
  export, theme, text-size; plus "Clear search")
- `Views/SidebarView.swift` — 9 sites
- `ContentView.swift` — 1 site (close file)
- `Views/MarkPopoverView.swift` — 2 sites
- `Views/ResolvedThreadsToggle.swift` — 1 site

No other behavior changes.

## Out of scope (deferred — add if full Dock fidelity is wanted later)

- Pointer/arrow triangle (Dock labels and modern macOS tooltips have none —
  omitting it is the accurate match, not a shortcut).
- Spring/scale entrance animation (fade only for v1).
- Per-tooltip delay configuration (fixed ~0.4s).

## Verification

- `swift build` compiles (Xcode 26 / macOS 26 SDK toolchain).
- `swift run ReaderMd`, then manually confirm:
  - Hovering each toolbar button shows a glass bubble below it after a short
    delay; no yellow system tooltip appears.
  - Bubble is horizontally centered on the control and doesn't run off screen
    edges.
  - A control near the screen bottom (e.g. a sidebar row when the window is
    low) flips the bubble above.
  - Moving off the control hides the bubble; sweeping across the toolbar
    doesn't leave stray bubbles.
  - VoiceOver still reads the tooltip text for each control.
- No unit test — this is hover/AppKit/window behavior, verified by running the
  app (consistent with the repo's testing note).
