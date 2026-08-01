import SwiftUI

/// Context-menu entries for handing a file to an external editor: the
/// remembered editor first, then Open With to pick (and remember) another.
/// Shared by every file row — tree, search results, recents.
/// `state` is passed in, not `@EnvironmentObject` — this body runs inside the
/// menu's own presentation host, where the environment doesn't reliably reach.
struct OpenWithMenu: View {
    let state: AppState
    let url: URL

    var body: some View {
        if state.isEditable(url) {
            if state.editorBundleID != nil {
                Button(state.openInEditorTitle) { state.openInEditor(url) }
            }
            // A LaunchServices query, so it runs when the menu opens rather than
            // on every row render. Empty for a file that no longer exists.
            let candidates = state.editorCandidates(for: url)
            if !candidates.isEmpty {
                Menu("Open With") {
                    ForEach(candidates, id: \.self) { app in
                        Button(state.editorName(app)) { state.openInEditor(url, using: app) }
                    }
                }
            }
        }
    }
}
