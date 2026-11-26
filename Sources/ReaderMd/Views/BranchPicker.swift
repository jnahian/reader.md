import SwiftUI

/// A git root's branch control in the sidebar (#110): it names what the root
/// shows — the checked-out branch, or the branch picked — and opens a popover to
/// read the root as it is on another branch, or go back to the working copy.
/// Picking checks nothing out; see `AppState.showBranch`.
struct BranchPicker: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var root: RootFolder
    @State private var showing = false
    @State private var refs: [String] = []
    @State private var query = ""

    var body: some View {
        Button { toggle() } label: {
            HStack(spacing: 3) {
                if root.extracting {
                    ProgressView().controlSize(.small).scaleEffect(0.55).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                }
                // `RootHeaderLayout` sets the width: the folder's name comes first.
                Text(root.branch?.ref ?? root.head ?? "")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            // The accent marks a root that isn't showing its working copy.
            .foregroundStyle(root.branch == nil ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.borderless)
        // The full name, which the label may have cut.
        .dockTooltip(root.branch.map { "Showing \($0.ref), read-only" }
                     ?? "On \(root.head ?? ""). Show another branch")
        .popover(isPresented: $showing, arrowEdge: .bottom) { chooser }
        // A stale query would silently hide branches the next time it opens.
        .onChange(of: showing) { open in if !open { query = "" } }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(text: "Show")
            ScopeRow(title: root.head.map { "Working copy (\($0))" } ?? "Working copy",
                     selected: root.branch == nil, tooltip: root.head) { pick(nil) }
            if !refs.isEmpty {
                Divider().padding(.vertical, 6)
                PopoverHeader(text: "Branches")
                RefList(refs: refs, selected: root.branch?.ref, query: $query) { pick($0) }
            }
        }
        .padding(10)
        .frame(width: 270)
    }

    /// Reads the branches, then opens. Read on each open: it's one git call,
    /// and a branch created in a terminal should be there without anything else
    /// having to notice it. Before opening, not after: a list that arrives once
    /// the popover is up leaves it sized for none, and the Branches header
    /// showed with no rows under it.
    private func toggle() {
        guard !showing else {
            showing = false
            return
        }
        let url = root.url
        Task {
            refs = await Task.detached(priority: .userInitiated) {
                GitDiff.branches(root: url, keepCurrent: true)
            }.value
            showing = true
        }
    }

    private func pick(_ ref: String?) {
        showing = false
        state.showBranch(ref, in: root)
    }
}
