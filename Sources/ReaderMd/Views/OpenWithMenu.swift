import SwiftUI

/// Context-menu entries for handing a file to an external editor: the
/// remembered editor first, then a picker for another.
/// Shared by every file row — tree, search results, recents.
///
/// Picking from the submenu also makes that app the ⇧⌘E editor, which is how the
/// setting is meant to be discovered. It's titled "Always Open With" rather than
/// "Open With" because that's Finder's wording for the same sticky choice — plain
/// "Open With" promises a one-off and would rebind ⇧⌘E behind the user's back.
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
                Menu("Always Open With") {
                    ForEach(candidates, id: \.self) { app in
                        Button(state.editorName(app)) { state.openInEditor(url, using: app) }
                    }
                }
            }
        }
    }
}
