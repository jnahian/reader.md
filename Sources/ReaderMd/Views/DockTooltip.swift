import SwiftUI
import AppKit

// MARK: - Public modifier

extension View {
    /// A Dock-style tooltip: a pill bubble with a pointer aimed at the control, shown on
    /// hover. Drop-in replacement for `.help(_:)` (which renders the yellow system tooltip).
    /// Also sets the accessibility label so VoiceOver keeps the hint text.
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

    func show(text: String, anchorScreenFrame anchor: NSRect) {
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
