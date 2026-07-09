import SwiftUI
import AppKit

enum ChromeMetrics {
    static let topBarHeight: CGFloat = 50
}

/// Vertically centers the native traffic-light buttons (close / minimize / zoom)
/// within the custom top bar's reserved space, and keeps them there across resizes.
struct TrafficLightConfigurator: NSViewRepresentable {
    var barHeight: CGFloat = ChromeMetrics.topBarHeight

    func makeNSView(context: Context) -> NSView {
        let view = ConfiguratorView()
        view.barHeight = barHeight
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ConfiguratorView)?.barHeight = barHeight
    }

    final class ConfiguratorView: NSView {
        var barHeight: CGFloat = ChromeMetrics.topBarHeight
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()

            guard let window = window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            // Let the SwiftUI content (our topbar) extend up under the titlebar so the
            // traffic lights sit on the same row as the toolbar buttons.
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            // Remove the hairline separator so the titlebar and our topbar read as one bar.
            window.titlebarSeparatorStyle = .none

            layoutButtons()

            let names: [NSNotification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    DispatchQueue.main.async { self?.layoutButtons() }
                }
                observers.append(token)
            }
        }

        /// Pins the traffic lights to a fixed inset and vertically centers them in the bar.
        func layoutButtons() {
            guard let window = window else { return }
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = types.compactMap { window.standardWindowButton($0) }
            guard let superview = buttons.first?.superview else { return }
            let leftInset: CGFloat = 16
            let spacing: CGFloat = 20   // standard center-to-center distance
            for (i, button) in buttons.enumerated() {
                let h = button.frame.height
                // superview top is anchored to the window top, so this is independent of its height.
                let y = superview.bounds.height - (barHeight + h) / 2
                let x = leftInset + CGFloat(i) * spacing
                button.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}
