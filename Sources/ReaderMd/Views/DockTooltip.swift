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
