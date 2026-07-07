import SwiftUI
import AppKit

/// A background surface that uses Apple's Liquid Glass (`glassEffect`) on macOS 26 (Tahoe)
/// and above, falling back to an `NSVisualEffectView` material on macOS 13–15.
///
/// Use as a `.background(...)`. Liquid Glass belongs on the *navigation / chrome* layer
/// (topbar, sidebar, outline, floating panels) — never behind scrolling content. Don't stack
/// glass *surfaces*, but interactive glass *controls* (e.g. the topbar buttons) may sit on a
/// glass surface when grouped in a `GlassEffectContainer` — that's the sanctioned Tahoe pattern.
struct GlassPanel: View {
    var cornerRadius: CGFloat = 0
    var material: NSVisualEffectView.Material = .sidebar

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: glassShape)
        } else {
            fallback
        }
    }

    @available(macOS 26.0, *)
    private var glassShape: AnyShape {
        cornerRadius > 0
            ? AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            : AnyShape(Rectangle())
    }

    @ViewBuilder private var fallback: some View {
        if cornerRadius > 0 {
            VisualEffectView(material: material)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            VisualEffectView(material: material)
        }
    }
}
