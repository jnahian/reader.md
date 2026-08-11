import SwiftUI
import AppKit

/// Hands the hosting `NSWindow` back to SwiftUI. Reader.md uses it to tell its
/// document window apart from the Settings window, which AppKit-level code
/// (the ⌘W key monitor) can't do from a SwiftUI view hierarchy alone.
///
/// The lookup is deferred: `makeNSView` runs before the view is in a window, so
/// `view.window` is nil there. Same tick-later pattern as the ⌘F focus grab
/// (`Toolbar.swift`) and the export panel (`MarkdownWebView.swift`).
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    /// Remembers the last window handed over, so the re-report below fires on an
    /// actual change rather than on every render. ContentView updates on sidebar
    /// drags, word counts, find state — each one would otherwise allocate and
    /// enqueue a block to re-announce the same window.
    final class Coordinator { weak var reported: NSWindow? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { report(view.window, to: context.coordinator) }
        return view
    }

    /// Still re-reports when the window changes: one can be torn down and
    /// rebuilt (a restored session, a closed-then-reopened window) and the weak
    /// reference on the other end would be nil after that. By update time the
    /// view is already in its window, so the common path is a pointer compare
    /// rather than a queued block per render.
    func updateNSView(_ view: NSView, context: Context) {
        guard view.window !== context.coordinator.reported else { return }
        DispatchQueue.main.async { report(view.window, to: context.coordinator) }
    }

    /// Deferred by both callers: `makeNSView` runs before the view is in a
    /// window, and reporting out of `updateNSView` would write to AppState from
    /// inside a SwiftUI update pass.
    private func report(_ window: NSWindow?, to coordinator: Coordinator) {
        guard let window, window !== coordinator.reported else { return }
        coordinator.reported = window
        onWindow(window)
    }
}
