import SwiftUI

/// A Finder / Tahoe–style toolbar icon button: borderless with a subtle rounded
/// hover and press background, dimming when disabled.
struct ToolbarIconButtonStyle: ButtonStyle {
    var width: CGFloat = 28
    var height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration, width: width, height: height)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        let width: CGFloat
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            styledLabel
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 && isEnabled }
        }

        // macOS 26: an interactive Liquid Glass surface (reacts to hover/press on
        // its own). Pre-26: the previous subtle rounded hover/press fill.
        @ViewBuilder private var styledLabel: some View {
            let label = configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: width, height: height)
            if #available(macOS 26.0, *) {
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
}
