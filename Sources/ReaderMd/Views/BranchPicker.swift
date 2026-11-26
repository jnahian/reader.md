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
        Button { showing.toggle() } label: {
            HStack(spacing: 3) {
                if root.extracting {
                    ProgressView().controlSize(.small).scaleEffect(0.55).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                }
                Text(root.branch?.ref ?? root.head ?? "")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 90, alignment: .leading)
            }
            .fixedSize()
            // The accent marks a root that isn't showing its working copy.
            .foregroundStyle(root.branch == nil ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .dockTooltip(root.branch.map { "Showing \($0.ref), read-only" } ?? "Show another branch")
        .popover(isPresented: $showing, arrowEdge: .bottom) { chooser }
        .onChange(of: showing) { open in
            if open { loadRefs() } else { query = "" }
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(text: "Show")
            ScopeRow(title: root.head.map { "Working copy (\($0))" } ?? "Working copy",
                     selected: root.branch == nil) { pick(nil) }
            if !refs.isEmpty {
                Divider().padding(.vertical, 6)
                PopoverHeader(text: "Branches")
                RefList(refs: refs, selected: root.branch?.ref, query: $query) { pick($0) }
            }
        }
        .padding(10)
        .frame(width: 270)
    }

    /// Read each time it opens: the list is one git call, and a branch created
    /// in a terminal should be there without anything else having to notice it.
    private func loadRefs() {
        let url = root.url
        Task {
            refs = await Task.detached(priority: .userInitiated) {
                GitDiff.branches(root: url, keepCurrent: true)
            }.value
        }
    }

    private func pick(_ ref: String?) {
        showing = false
        state.showBranch(ref, in: root)
    }
}
