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

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    /// Re-reports on every update: a window can be torn down and rebuilt (a
    /// restored session, a closed-then-reopened window) and the weak reference
    /// on the other end would be nil after that.
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
    }
}
