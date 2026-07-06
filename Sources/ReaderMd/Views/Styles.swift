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
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fillColor)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 && isEnabled }
        }

        private var fillColor: Color {
            if configuration.isPressed { return Color.primary.opacity(0.14) }
            if hovering { return Color.primary.opacity(0.07) }
            return .clear
        }
    }
}
