import SwiftUI

/// Status-bar control toggling whether resolved comment threads (#3) still
/// render their (de-emphasized) anchor in the content, or are hidden
/// entirely. Only shown once at least one thread has been resolved.
struct ResolvedThreadsToggle: View {
    @EnvironmentObject var state: AppState

    private var resolvedCount: Int { state.marks.filter { $0.resolved }.count }

    var body: some View {
        if resolvedCount > 0 {
            Button {
                state.toggleShowResolvedThreads()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.showResolvedThreads ? "checkmark.circle.fill" : "checkmark.circle")
                    Text("\(resolvedCount)")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.showResolvedThreads ? Color.secondary : Color.accentColor)
            .font(.system(size: 11))
            .help(state.showResolvedThreads ? "Hide resolved threads" : "Show resolved threads")
        }
    }
}
