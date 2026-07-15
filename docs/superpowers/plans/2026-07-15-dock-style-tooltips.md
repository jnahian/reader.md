# Dock-Style Tooltips Implementation Plan

> **Status: superseded.** The glass-bubble design in this plan was dropped during implementation in favor of a hand-drawn pill + pointer (plain `NSView`, no `NSGlassEffectView`). This plan is kept for history; the source of truth is `Sources/ReaderMd/Views/DockTooltip.swift`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the standard macOS yellow tooltip (`.help()`) with a rounded Liquid Glass bubble shown on hover, matching the app's chrome, on every control that currently uses `.help()`.

**Architecture:** One new file adds a `.dockTooltip(_:)` view modifier. The modifier attaches a zero-size `NSTrackingArea`-backed background view that reports hover enter/exit and the control's on-screen frame to a `TooltipController` singleton, which shows/moves/hides a single reused borderless `NSPanel`. The panel's content is a rounded glass bubble (`NSGlassEffectView` on macOS 26, `NSVisualEffectView(.toolTip)` fallback on 13–15). All 22 `.help(…)` call sites are then swapped to `.dockTooltip(…)`.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit, `NSPanel`, `NSTrackingArea`, `NSGlassEffectView`.

## Global Constraints

- Build toolchain: Xcode 26 / Swift 6.2+ with the macOS 26 SDK (`NSGlassEffectView` only exists there).
- Deployment target stays **macOS 13**: every macOS 26-only API must sit behind `if #available(macOS 26.0, *)` with a pre-26 fallback.
- App is not sandboxed; no security-scoped anything needed here.
- Verification is by **`swift build` + running the app** — this is hover/AppKit/window behavior with no unit-test surface. `swift test` only covers `fuzzyScore`; do not add a test target for this.
- Reuse the existing glass/fallback pattern from `Views/GlassPanel.swift` (glass on 26, `NSVisualEffectView` on 13–15). Do not add dependencies.

---

### Task 1: `DockTooltip.swift` — controller, tracker, and modifier

**Files:**
- Create: `Sources/ReaderMd/Views/DockTooltip.swift`

**Interfaces:**
- Consumes: nothing (self-contained; AppKit + SwiftUI only).
- Produces:
  - `extension View { func dockTooltip(_ text: String) -> some View }` — the modifier used at every call site in Task 2.
  - `TooltipController` (`@MainActor` singleton, `TooltipController.shared`) with `show(text: String, anchorScreenFrame: NSRect)` and `hide()`.
  - `TrackerNSView` (`NSView` subclass) and `TooltipTracker` (`NSViewRepresentable`) — internal; not used outside this file.

- [ ] **Step 1: Write the file**

Create `Sources/ReaderMd/Views/DockTooltip.swift` with exactly this content:

```swift
import SwiftUI
import AppKit

// MARK: - Public modifier

extension View {
    /// A Dock-style tooltip: a rounded Liquid Glass bubble shown on hover, matching the
    /// app's chrome. Drop-in replacement for `.help(_:)` (which renders the yellow system
    /// tooltip). Also sets the accessibility label so VoiceOver keeps the hint text.
    func dockTooltip(_ text: String) -> some View {
        self
            .background(TooltipTracker(text: text))
            .accessibilityLabel(text)
    }
}

// MARK: - Hover tracker

/// Zero-footprint background view that reports hover enter/exit for its host control.
private struct TooltipTracker: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TrackerNSView { TrackerNSView() }

    func updateNSView(_ view: TrackerNSView, context: Context) {
        view.text = text
    }
}

final class TrackerNSView: NSView {
    var text: String = ""
    private var timer: Timer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showTooltip() }
        }
    }

    override func mouseExited(with event: NSEvent) {
        timer?.invalidate()
        timer = nil
        TooltipController.shared.hide()
    }

    private func showTooltip() {
        guard let window, !text.isEmpty else { return }
        let screenFrame = window.convertToScreen(convert(bounds, to: nil))
        TooltipController.shared.show(text: text, anchorScreenFrame: screenFrame)
    }

    deinit { timer?.invalidate() }
}

// MARK: - Shared floating panel

@MainActor
final class TooltipController {
    static let shared = TooltipController()

    private let panel: NSPanel
    private let label: NSTextField
    private let container: NSView
    private let gap: CGFloat = 6

    private init() {
        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
        ])

        let content: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 8
            glass.contentView = container
            content = glass
        } else {
            let vev = NSVisualEffectView()
            vev.material = .toolTip
            vev.blendingMode = .behindWindow
            vev.state = .active
            vev.wantsLayer = true
            vev.layer?.cornerRadius = 8
            vev.layer?.masksToBounds = true
            vev.addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: vev.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: vev.trailingAnchor),
                container.topAnchor.constraint(equalTo: vev.topAnchor),
                container.bottomAnchor.constraint(equalTo: vev.bottomAnchor),
            ])
            content = vev
        }

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentView = content
    }

    func show(text: String, anchorScreenFrame: NSRect) {
        label.stringValue = text
        let size = container.fittingSize
        let origin = position(size: size, anchor: anchorScreenFrame)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            panel.orderOut(nil)
        }
    }

    /// Center horizontally on the control, clamped to the screen; place below the control,
    /// flipping above when there's no room below. Screen coords: origin bottom-left, y up.
    private func position(size: NSSize, anchor: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var x = anchor.midX - size.width / 2
        x = min(max(x, visible.minX + 4), visible.maxX - size.width - 4)

        var y = anchor.minY - gap - size.height   // below the control
        if y < visible.minY { y = anchor.maxY + gap }  // no room below → flip above
        return NSPoint(x: x, y: y)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds. If `NSGlassEffectView`, `cornerRadius`, or `contentView` are reported unknown, the toolchain is not Xcode 26 / macOS 26 SDK — stop and fix the toolchain (see Global Constraints). If a Swift 6 concurrency error appears on the `Timer` closure, confirm `MainActor.assumeIsolated { … }` wraps the `self?.showTooltip()` call exactly as written.

- [ ] **Step 3: Commit**

```bash
git add Sources/ReaderMd/Views/DockTooltip.swift
git commit -m "feat: add Dock-style glass tooltip modifier"
```

---

### Task 2: Swap all `.help(…)` call sites to `.dockTooltip(…)`

**Files:**
- Modify: `Sources/ReaderMd/Views/Toolbar.swift` (9 sites)
- Modify: `Sources/ReaderMd/Views/SidebarView.swift` (9 sites)
- Modify: `Sources/ReaderMd/Views/MarkPopoverView.swift` (2 sites)
- Modify: `Sources/ReaderMd/ContentView.swift` (1 site)
- Modify: `Sources/ReaderMd/Views/ResolvedThreadsToggle.swift` (1 site)

**Interfaces:**
- Consumes: `dockTooltip(_:)` from Task 1.
- Produces: nothing new.

The swap is purely textual: `.help(` → `.dockTooltip(`. The argument expressions (string literals and ternaries) are unchanged. `ReaderMdApp.swift`'s `CommandGroup(replacing: .help)` is the Help *menu*, not a tooltip — it does not match `.help(` and must not be touched.

- [ ] **Step 1: Replace in every file**

Run:

```bash
cd /Users/nahian/Projects/reader.md
for f in Sources/ReaderMd/Views/Toolbar.swift \
         Sources/ReaderMd/Views/SidebarView.swift \
         Sources/ReaderMd/Views/MarkPopoverView.swift \
         Sources/ReaderMd/ContentView.swift \
         Sources/ReaderMd/Views/ResolvedThreadsToggle.swift; do
  sed -i '' 's/\.help(/.dockTooltip(/g' "$f"
done
```

- [ ] **Step 2: Verify no `.help(` tooltip calls remain and the menu is untouched**

Run: `grep -rn "\.help(" Sources/ReaderMd`
Expected: **no output** (all 22 converted).

Run: `grep -rn "replacing: .help" Sources/ReaderMd/ReaderMdApp.swift`
Expected: still one line — the Help menu, untouched.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/ReaderMd/Views/Toolbar.swift Sources/ReaderMd/Views/SidebarView.swift \
        Sources/ReaderMd/Views/MarkPopoverView.swift Sources/ReaderMd/ContentView.swift \
        Sources/ReaderMd/Views/ResolvedThreadsToggle.swift
git commit -m "feat: use Dock-style tooltips in place of .help()"
```

---

### Task 3: Manual verification in the running app

**Files:** none (verification only).

**Interfaces:** none.

- [ ] **Step 1: Launch the app**

Run: `swift run ReaderMd`
Add a folder if needed so the sidebar and a document are visible.

- [ ] **Step 2: Confirm the behavior**

Check each, and confirm **no yellow system tooltip appears** anywhere:

1. Hover a toolbar button (e.g. sidebar toggle, reload, export). After ~0.4s a rounded glass bubble appears **below** it with the label text; on macOS 26 it is Liquid Glass, on 13–15 it is the translucent tooltip material.
2. The bubble is horizontally centered on the control and does not run off the left/right screen edges (test the leftmost and rightmost toolbar controls).
3. Hover a control near the **bottom** of the screen (move the window low, hover a sidebar row's action button) — the bubble flips to appear **above** the control.
4. Move off the control → the bubble fades out. Sweep quickly across the toolbar → no stray bubbles are left behind.
5. Enable VoiceOver (⌘F5) and focus a converted control → it still speaks the tooltip text.

- [ ] **Step 3: Note any failures**

If any check fails, fix in `DockTooltip.swift` and re-run. Do not mark the task complete until all five pass.

---

## Self-Review

- **Spec coverage:** NSPanel controller (Task 1), NSTrackingArea tracker (Task 1), `.dockTooltip` modifier + accessibility (Task 1), `NSGlassEffectView` with `.toolTip` fallback behind availability guard (Task 1), below/flip-above positioning + edge clamp (Task 1 `position`), fade animation (Task 1), 0.4s delay (Task 1), all 22 call-site swaps across the 5 named files leaving the Help menu untouched (Task 2), run-the-app verification incl. VoiceOver (Task 3). All spec sections covered.
- **Placeholder scan:** none — complete code and exact commands throughout.
- **Type consistency:** `TooltipController.shared`, `show(text:anchorScreenFrame:)`, `hide()`, `dockTooltip(_:)` used identically in Tasks 1 and 2.
