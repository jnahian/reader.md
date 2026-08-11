import SwiftUI
import AppKit

// MARK: - Public modifier

extension View {
    /// A Dock-style tooltip: a pill bubble with a pointer aimed at the control, shown on
    /// hover. Drop-in replacement for `.help(_:)` (which renders the yellow system tooltip).
    /// Also sets the accessibility label so VoiceOver keeps the hint text.
    ///
    /// Pass `accessibility` where the bubble names a *state* rather than an action: the
    /// icon conveys that state to sighted users, but a button's VoiceOver label has to say
    /// what pressing it does.
    func dockTooltip(_ text: String, accessibility: String? = nil) -> some View {
        self
            .background(TooltipTracker(text: text))
            .accessibilityLabel(accessibility ?? text)
    }
}

// MARK: - Hover tracker

/// Zero-footprint background view that reports hover enter/exit for its host control.
private struct TooltipTracker: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TrackerNSView { TrackerNSView() }

    func updateNSView(_ view: TrackerNSView, context: Context) {
        guard view.text != text else { return }
        view.text = text
        // The label can change while its bubble is already up — clicking the
        // appearance button relabels it under the cursor. Without this the
        // bubble keeps the old text until the next hover.
        TooltipController.shared.relabel(text, owner: view)
    }
}

final class TrackerNSView: NSView {
    var text: String = ""
    private var timer: Timer?
    private var clickMonitor: Any?
    /// Whether the cursor is over this control. Tracked explicitly rather than
    /// left implicit in AppKit's enter/exit pairing, because `syncHover` has to
    /// synthesize the events AppKit doesn't send — see there.
    private var inside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            // .assumeInside: a control created under a stationary cursor gets no
            // mouseEntered, so without this AppKit also withholds the matching
            // mouseExited when the mouse finally leaves, stranding the bubble.
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .assumeInside],
            owner: self
        ))
        syncHover()
    }

    /// Re-derive hover from where the cursor actually is. AppKit only reports
    /// enter/exit for a *moving* mouse: a control that appears under a stationary
    /// cursor never gets `mouseEntered`, and one that slides out from under it
    /// never gets `mouseExited`. Removing the last row of a sidebar section
    /// collapses the whole section — header, rows and trailing spacer — so a
    /// control from the neighbouring section lands under a cursor that never
    /// moved. That is how the Recents and Favorites × bubbles ended up crossed:
    /// the removed row's label stayed up over the row that replaced it, and the
    /// replacement's own bubble never armed until the mouse was jiggled.
    /// Tracking areas are rebuilt on every geometry change, which is exactly when
    /// this can happen, so that is where it runs.
    private func syncHover() {
        guard let window, window.isKeyWindow else {
            if inside { endHover() }
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let over = visibleRect.contains(point)
        if over, !inside {
            beginHover()
        } else if !over, inside {
            endHover()
        } else if over {
            // Still the hovered control, but it moved — re-aim the pointer.
            TooltipController.shared.reanchor(owner: self)
        }
    }

    override func mouseEntered(with event: NSEvent) { beginHover() }

    override func mouseExited(with event: NSEvent) { endHover() }

    private func beginHover() {
        guard !inside else { return }
        inside = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showTooltip() }
        }
        // A click should dismiss the bubble (and cancel a pending one), but the
        // click lands on the control itself, never on this background view — and
        // if it opens a menu or popover, the mouseExited may never arrive. Watch
        // for it with a monitor scoped to the hover.
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.timer?.invalidate()
                    self.timer = nil
                    // Own bubble only: nested trackers (a row and the × inside it)
                    // both see this click, and the one that doesn't own the bubble
                    // must not tear down the one that does.
                    TooltipController.shared.hideIfOwner(self)
                }
                return event
            }
        }
    }

    private func endHover() {
        inside = false
        removeClickMonitor()
        timer?.invalidate()
        timer = nil
        TooltipController.shared.hideIfOwner(self)
    }

    // If the control is removed while its tooltip is showing (e.g. clicking a button
    // that dismisses its popover), no mouseExited arrives — hide here so the bubble
    // isn't stranded on screen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endHover() } else { syncHover() }
    }

    private func removeClickMonitor() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func showTooltip() {
        guard let window, !text.isEmpty else { return }
        let screenFrame = window.convertToScreen(convert(bounds, to: nil))
        TooltipController.shared.show(text: text, anchorScreenFrame: screenFrame, owner: self)
    }

    deinit {
        timer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }
}

// MARK: - Shared floating panel

/// Renders the Dock's tooltip look: a full-pill capsule with a pointer triangle aimed at the
/// control, drawn in a plain `NSView` (no `NSVisualEffectView`, so macOS 26 draws no Liquid-Glass
/// rim). A soft `NSShadow` gives the glass-pill lift; the pill sits inside a transparent margin
/// so that shadow isn't clipped.
@MainActor
final class TooltipController {
    static let shared = TooltipController()

    private let panel: NSPanel
    private let container = NSView()
    private let pill = PillView()
    private let label: NSTextField
    private weak var owner: TrackerNSView?   // control the currently-shown bubble belongs to
    private var currentText = ""             // what the bubble reads right now, for re-anchoring
    private var fadeGeneration = 0           // invalidates an in-flight fade-out

    private let hPad: CGFloat = 16    // capsule horizontal inset
    private let vPad: CGFloat = 6     // capsule vertical inset
    private let pointerW: CGFloat = 16
    private let pointerH: CGFloat = 7
    private let gap: CGFloat = 1      // slack between pointer tip and the control
    private let shadowPad: CGFloat = 10  // transparent margin around the pill for the drop shadow

    private init() {
        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.alignment = .center

        pill.pointerW = pointerW
        pill.pointerH = pointerH
        pill.alphaValue = 0.96           // slight translucency, applied uniformly over opaque fills
        pill.wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 7
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        pill.shadow = shadow
        pill.addSubview(label)
        container.addSubview(pill)

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = false   // the window shadow reads as a gray border; use the soft NSShadow instead
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentView = container
    }

    func show(text: String, anchorScreenFrame anchor: NSRect, owner: TrackerNSView) {
        self.owner = owner
        layout(text: text, anchorScreenFrame: anchor)

        // Claim the panel from any fade-out still running, so its completion
        // handler doesn't order this bubble straight back out. Only restart from
        // transparent when the panel is actually down — a bubble handed from one
        // control to the next should slide, not blink.
        fadeGeneration &+= 1
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFront(nil)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    /// Re-render the visible bubble in place when its control's label changed.
    /// Re-measures the control too: a relabel usually comes with a new icon, so
    /// the button's width — and the pointer's target — shifts with it.
    func relabel(_ text: String, owner view: TrackerNSView) {
        guard owner === view, panel.isVisible, let window = view.window else { return }
        layout(text: text,
               anchorScreenFrame: window.convertToScreen(view.convert(view.bounds, to: nil)))
    }

    /// Re-aim the visible bubble after its control moved without the cursor
    /// leaving it — a row removed above slides the control up under the pointer.
    func reanchor(owner view: TrackerNSView) {
        guard owner === view else { return }
        relabel(currentText, owner: view)
    }

    private func layout(text: String, anchorScreenFrame anchor: NSRect) {
        currentText = text
        label.stringValue = text
        label.sizeToFit()
        let labelSize = label.frame.size

        let capsuleH = ceil(labelSize.height) + vPad * 2
        let width = ceil(labelSize.width) + hPad * 2
        let radius = capsuleH / 2
        let pillSize = NSSize(width: width, height: capsuleH + pointerH)

        let p = placement(total: pillSize, anchor: anchor, radius: radius)

        let panelSize = NSSize(width: pillSize.width + shadowPad * 2,
                               height: pillSize.height + shadowPad * 2)
        panel.setFrame(NSRect(x: p.origin.x - shadowPad, y: p.origin.y - shadowPad,
                              width: panelSize.width, height: panelSize.height), display: true)
        container.frame = NSRect(origin: .zero, size: panelSize)

        pill.frame = NSRect(x: shadowPad, y: shadowPad, width: pillSize.width, height: pillSize.height)
        pill.pointerOnTop = p.pointerOnTop
        pill.tipX = p.tipX
        pill.radius = radius
        pill.capsuleH = capsuleH
        pill.needsDisplay = true

        let capsuleBottom = p.pointerOnTop ? 0 : pointerH
        label.frame = NSRect(x: hPad, y: capsuleBottom + vPad,
                             width: ceil(labelSize.width), height: ceil(labelSize.height))
    }

    private func hide() {
        owner = nil
        guard panel.isVisible else { return }
        fadeGeneration &+= 1
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { TooltipController.shared.finishFade(generation) }
        }
    }

    /// Order the panel out only if nothing claimed it during the fade. A control
    /// that slid under the cursor can `show` inside that 100 ms window, and an
    /// unconditional `orderOut` here would hide the bubble it just put up.
    private func finishFade(_ generation: Int) {
        guard fadeGeneration == generation else { return }
        panel.orderOut(nil)
    }

    /// Hide only if the bubble currently belongs to `view` — avoids a torn-down control
    /// hiding a tooltip that has since moved to a different control. The only way in:
    /// an unscoped hide is what let one sidebar row cancel its neighbour's bubble.
    func hideIfOwner(_ view: TrackerNSView) {
        if owner === view { hide() }
    }


    private struct Placement { var origin: NSPoint; var pointerOnTop: Bool; var tipX: CGFloat }

    /// Center on the control and clamp to the screen. Sit below the control (pointer up), or
    /// flip above (pointer down) when there's no room. Screen coords: origin bottom-left, y up.
    private func placement(total: NSSize, anchor: NSRect, radius: CGFloat) -> Placement {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var x = anchor.midX - total.width / 2
        x = min(max(x, visible.minX + 4), visible.maxX - total.width - 4)

        var pointerOnTop = true
        var y = anchor.minY - gap - total.height   // below the control
        if y < visible.minY {                      // no room below → flip above
            pointerOnTop = false
            y = anchor.maxY + gap
        }

        // Aim the pointer at the control's center, kept on the flat span of the pill.
        let minTip = radius + pointerW / 2
        let maxTip = total.width - radius - pointerW / 2
        var tipX = anchor.midX - x
        tipX = minTip <= maxTip ? min(max(tipX, minTip), maxTip) : total.width / 2

        return Placement(origin: NSPoint(x: x, y: y), pointerOnTop: pointerOnTop, tipX: tipX)
    }
}

/// Draws the pill and pointer as two separate opaque fills. Two fills (not one path) avoids a
/// winding-rule hole where the overlapping subpaths would cancel; opaque avoids the overlap
/// double-blending. The view's `alphaValue` then applies the translucency uniformly.
private final class PillView: NSView {
    var pointerOnTop = true
    var tipX: CGFloat = 0
    var radius: CGFloat = 0
    var capsuleH: CGFloat = 0
    var pointerW: CGFloat = 16
    var pointerH: CGFloat = 7

    private let fill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.22, alpha: 1.0)
            : NSColor(white: 1.0, alpha: 1.0)
    }

    private let overlap: CGFloat = 4   // sink the pointer base into the pill so they merge

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()

        let capsuleY: CGFloat = pointerOnTop ? 0 : pointerH
        NSBezierPath(roundedRect: NSRect(x: 0, y: capsuleY, width: bounds.width, height: capsuleH),
                     xRadius: radius, yRadius: radius).fill()

        let tri = NSBezierPath()
        if pointerOnTop {
            tri.move(to: NSPoint(x: tipX - pointerW / 2, y: capsuleH - overlap))
            tri.line(to: NSPoint(x: tipX, y: bounds.height))
            tri.line(to: NSPoint(x: tipX + pointerW / 2, y: capsuleH - overlap))
        } else {
            tri.move(to: NSPoint(x: tipX - pointerW / 2, y: pointerH + overlap))
            tri.line(to: NSPoint(x: tipX, y: 0))
            tri.line(to: NSPoint(x: tipX + pointerW / 2, y: pointerH + overlap))
        }
        tri.close()
        tri.fill()
    }
}
