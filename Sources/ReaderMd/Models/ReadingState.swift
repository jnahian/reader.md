import Foundation

/// Scroll-rate state, deliberately kept OFF `AppState`.
///
/// bridge.js posts `progress` on every scroll event (~60–120/s). While these two
/// values lived on `AppState`, each post invalidated every view observing it —
/// including all ~3k sidebar rows, since `FileTreeRow` holds an
/// `@EnvironmentObject`. Measured: 120 posts caused 63,308 `FileTreeRow` body
/// evaluations and pinned the main thread. Only `ReadingProgressBar` and
/// `TOCView` read these, so they observe this object instead.
///
/// Anything published at scroll/keystroke rate belongs here, not on `AppState`.
@MainActor
final class ReadingState: ObservableObject {
    @Published var progress: Double = 0      // 0...1
    @Published var activeHeadingID: String?

    /// Called when the open document changes — a fresh document starts unread.
    func reset() {
        progress = 0
        activeHeadingID = nil
    }
}
