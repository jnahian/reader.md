import SwiftUI

/// Color-swatch picker shown in a native NSPopover over the WKWebView: on a
/// fresh selection (create) or on tapping an existing highlight (edit/remove).
struct HighlightSwatchView: View {
    var existingColor: HighlightColor?
    var onPick: (HighlightColor) -> Void
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button { onPick(color) } label: {
                    Circle()
                        .fill(color.swiftUIColor)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: existingColor == color ? 2 : 0)
                                .padding(-2)
                        )
                }
                .buttonStyle(.plain)
            }

            if let onRemove {
                Divider().frame(height: 18)
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
