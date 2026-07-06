import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search field — Finder-style capsule
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
                TextField("Search", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !state.searchQuery.isEmpty {
                    Button { state.searchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)

            // Tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    // Recents section
                    if state.normalizedQuery.isEmpty && !state.recentFiles.isEmpty {
                        sectionHeader("RECENTS")
                        ForEach(state.recentFiles.prefix(6), id: \.self) { path in
                            RecentRow(path: path)
                        }
                        Spacer().frame(height: 10)
                    }

                    sectionHeader("FOLDERS")

                    if state.roots.isEmpty {
                        Text("No folders yet")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                    }
                    ForEach(state.roots) { root in
                        RootSectionView(root: root)
                    }
                    if searchYieldsNothing {
                        Text("No matching files")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.5)

            // Bottom add-folder bar, like Finder's sidebar footer controls
            HStack(spacing: 4) {
                Button { state.pickFolders() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                        Text("Add Folder")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add folder (⌘O)")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(GlassPanel())
        .onChange(of: state.focusSearch) { _ in searchFocused = true }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchYieldsNothing: Bool {
        let q = state.normalizedQuery
        guard !q.isEmpty, !state.roots.isEmpty else { return false }
        return !state.roots.contains { root in root.children.contains { $0.matches(q) } }
    }
}

/// A row in the sidebar Recents section.
struct RecentRow: View {
    @EnvironmentObject var state: AppState
    let path: String
    @State private var hovering = false

    private var isSelected: Bool { state.selectedFile?.url.path == path }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 10)
            Image(systemName: "clock")
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor
                      : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { state.openPath(path) }
    }
}

/// A single root folder header + its filtered contents.
struct RootSectionView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var root: RootFolder
    @State private var expanded = true
    @State private var hovering = false

    var body: some View {
        let q = state.normalizedQuery
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                Text(root.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering {
                    Button { state.removeRoot(root) } label: {
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove folder")
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } }
            .onHover { hovering = $0 }

            if expanded || !q.isEmpty {
                ForEach(root.children.filter { $0.matches(q) }) { node in
                    FileTreeRow(node: node, depth: 1, query: q)
                }
            }
        }
    }
}
