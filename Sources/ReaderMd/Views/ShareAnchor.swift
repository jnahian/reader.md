import SwiftUI
import AppKit

/// The view the system share sheet points at.
///
/// `NSSharingServicePicker.show(relativeTo:of:)` needs a real `NSView`, and a
/// SwiftUI toolbar item hands you none. Parking a zero-footprint view behind the
/// export menu's label gives the sheet the button's own frame to hang from —
/// the same trick `DockTooltip` uses to get a toolbar control's rect.
///
/// The first attempt anchored to the web view's top-trailing corner instead,
/// which is not where the button is: with the outline open that corner sits at
/// the outline's edge, so the sheet appeared over the outline pane rather than
/// under the button that opened it.
enum ShareAnchor {
    /// Weak: the toolbar owns the view, and it goes away with the window.
    /// `presentSharePicker` falls back to the web view if it is gone.
    @MainActor static weak var view: NSView?

    /// Applied as a `.background` of the export menu.
    struct Marker: NSViewRepresentable {
        func makeNSView(context: Context) -> AnchorNSView {
            let view = AnchorNSView()
            ShareAnchor.view = view
            return view
        }

        /// Re-registered on every pass: the toolbar rebuilds its items whenever a
        /// command's disabled state changes, so the view registered at creation
        /// is not necessarily the one still on screen.
        func updateNSView(_ nsView: AnchorNSView, context: Context) {
            ShareAnchor.view = nsView
        }
    }

    final class AnchorNSView: NSView {
        /// Never take a mouse event. `.background` puts this over the whole
        /// control, and a plain NSView returns itself here — which would eat the
        /// click that opens the menu. Same reason `TrackerNSView` declines.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
