import SwiftUI

/// Floating in-page find bar; drives the WKWebView's native find via AppState.
struct FindBar: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Find in page", text: $state.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(width: 160)
                .focused($focused)
                .onSubmit { state.triggerFindNext() }

            Divider().frame(height: 14)

            Button { state.triggerFindPrev() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(state.findQuery.isEmpty)

            Button { state.triggerFindNext() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(state.findQuery.isEmpty)

            Button { close() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlassPanel(cornerRadius: 12, material: .hudWindow))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 3)
        .onAppear { focused = true }
    }

    private func close() {
        state.findQuery = ""
        state.showFind = false
    }
}
