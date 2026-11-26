import SwiftUI

/// The topbar's diff-scope control: a button naming what the diff compares
/// against, opening a popover that lists the three fixed scopes and the repo's
/// branches.
///
/// A popover rather than the pull-down `Picker` it replaces. `GitDiff.branches`
/// offers every ref in the repo, and an NSMenu-backed picker shows them as one flat run
/// of rows with no way to narrow it — you scroll the whole repo looking for a
/// branch you already know the name of. The popover keeps the branches in their
/// own scrolling section under a filter field, separates them from the three
/// scopes that exist in every repo, and scrolls the current selection into view
/// when it opens.
///
/// For a document read from a branch view (#110) it picks the base instead: the
/// diff is then what the branch changed since it forked from that base, and the
/// three fixed scopes, which are about the working tree and the index, don't apply.
struct DiffScopePicker: View {
    @EnvironmentObject var state: AppState
    @State private var showing = false
    @State private var query = ""

    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                // A branch name has no bound; cap the label rather than let one
                // ref push the find field off the toolbar.
                Text(label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            // The cluster's button style sizes icon cells, not this one, so the
            // breathing room inside the hover pill comes from the label.
            .padding(.horizontal, 10)
        }
        .dockTooltip(state.branchViewRoot == nil
                     ? "What the diff compares against"
                     : "Where the diff starts: the fork point with this branch")
        .popover(isPresented: $showing, arrowEdge: .top) { chooser }
        // A stale query would silently hide branches the next time it opens.
        .onChange(of: showing) { open in if !open { query = "" } }
    }

    private var label: String {
        guard let root = state.branchViewRoot else { return state.diffScope.displayName }
        return "vs \(state.branchDiffBaseName(for: root))"
    }

    // MARK: - Popover

    @ViewBuilder private var chooser: some View {
        if let root = state.branchViewRoot {
            VStack(alignment: .leading, spacing: 0) {
                PopoverHeader(text: "Changes since forking from")
                if state.diffBranches.isEmpty {
                    Text("No other branches")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    RefList(refs: state.diffBranches, selected: state.branchDiffBaseName(for: root),
                            query: $query) { name in
                        state.setBranchDiffBase(name, for: root)
                        showing = false
                    }
                }
            }
            .padding(10)
            .frame(width: 270)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                PopoverHeader(text: "Compare against")
                ForEach(DiffScope.fixed, id: \.self) { scope in
                    ScopeRow(title: scope.displayName,
                             selected: scope == state.diffScope) { pick(scope) }
                }

                if !refs.isEmpty {
                    Divider().padding(.vertical, 6)
                    PopoverHeader(text: "Branches")
                    RefList(refs: refs, selected: selectedRef, query: $query) { pick(.ref($0)) }
                }
            }
            .padding(10)
            .frame(width: 270)
        }
    }

    /// Every ref the scope menu offers, taken from `diffScopeChoices` rather
    /// than `diffBranches` so a selected ref the repo no longer lists (the open
    /// file moved to another repo) still appears — and stays reselectable.
    private var refs: [String] {
        state.diffScopeChoices.compactMap { scope -> String? in
            guard case .ref(let name) = scope else { return nil }
            return name
        }
    }

    private var selectedRef: String? {
        guard case .ref(let name) = state.diffScope else { return nil }
        return name
    }

    private func pick(_ scope: DiffScope) {
        state.setDiffScope(scope)
        showing = false
    }
}

/// The branch section of a ref popover — the diff scope's, and the sidebar's
/// branch picker: a filter field once the list is long, then the refs in a
/// scrolling list that opens on the one selected.
struct RefList: View {
    let refs: [String]
    let selected: String?
    @Binding var query: String
    let pick: (String) -> Void
    @FocusState private var filterFocused: Bool

    /// Below this many branches the filter field is more chrome than help — the
    /// whole list is on screen already.
    private static let filterThreshold = 8

    private var filtered: [String] { GitDiff.filterBranches(refs, query: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if refs.count >= Self.filterThreshold { filterField }
            branchList
        }
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter branches", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($filterFocused)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.1)))
        .padding(.bottom, 4)
        // The popover takes key focus a runloop turn after it appears; setting
        // focus synchronously here is clobbered by that.
        .onAppear { DispatchQueue.main.async { filterFocused = true } }
    }

    @ViewBuilder private var branchList: some View {
        if filtered.isEmpty {
            Text("No matching branches")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.self) { name in
                            ScopeRow(title: name, selected: selected == name, tooltip: name) { pick(name) }
                                .id(name)
                        }
                    }
                }
                .frame(maxHeight: 220)
                // A long ref list doesn't fit; open on the one in use rather than at the top.
                .onAppear {
                    guard let selected else { return }
                    DispatchQueue.main.async { proxy.scrollTo(selected, anchor: .center) }
                }
            }
        }
    }
}

/// A ref popover's section label.
struct PopoverHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
    }
}

/// One row of the chooser: a checkmark column so the rows stay aligned whether
/// or not they're selected, and a hover fill matching the sidebar's.
struct ScopeRow: View {
    let title: String
    let selected: Bool
    /// The full name, for a row whose title can be cut short: branches.
    var tooltip: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .opacity(selected ? 1 : 0)
                .frame(width: 12)
            Text(title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .rowButton(action)
        .accessibilityAddTraits(traits)
        .modifier(OptionalTooltip(text: tooltip))
    }

    /// `.isButton` used to be spelled out here because the row was an
    /// `.onTapGesture` on an `HStack`; as a real Button it carries that itself.
    private var traits: AccessibilityTraits { selected ? [.isSelected] : [] }
}

private struct OptionalTooltip: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text { content.dockTooltip(text) } else { content }
    }
}
