import SwiftUI

/// A Finder / Tahoe–style toolbar icon button: borderless with a subtle rounded
/// hover and press background, dimming when disabled.
struct ToolbarIconButtonStyle: ButtonStyle {
    /// nil = size to the label (e.g. the sidebar footer's text buttons).
    var width: CGFloat? = 34
    var height: CGFloat? = 30
    /// When false, the button never draws its own glass surface — use inside a
    /// grouped glass capsule so glass isn't stacked (only the subtle hover fill).
    var glass: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, width: width, height: height, glass: glass)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        let width: CGFloat?
        let height: CGFloat?
        let glass: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            styledLabel
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 && isEnabled }
        }

        // macOS 26: an interactive Liquid Glass surface (reacts to hover/press on
        // its own). Pre-26, or when grouped in a capsule: the subtle hover/press fill.
        @ViewBuilder private var styledLabel: some View {
            let label = configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: width, height: height)
            if glass, #available(macOS 26.0, *) {
                label.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                label.background(Capsule().fill(fillColor))
            }
        }

        private var fillColor: Color {
            if configuration.isPressed { return Color.primary.opacity(0.14) }
            if hovering { return Color.primary.opacity(0.07) }
            return .clear
        }
    }
}

extension View {
    /// Interactive Liquid Glass capsule for topbar controls that aren't plain
    /// Buttons (e.g. the typography Menu) on macOS 26; a no-op below.
    @ViewBuilder func toolbarGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
        }
    }

    /// A grouped glass capsule (e.g. the sidebar footer add-buttons or a topbar
    /// button cluster): interactive Liquid Glass on macOS 26, a subtle fill +
    /// stroke that brightens on hover below.
    @ViewBuilder func glassCapsule(hovering: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(Capsule().fill(Color.primary.opacity(hovering ? 0.10 : 0.06)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        }
    }
}
