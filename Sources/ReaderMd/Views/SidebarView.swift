import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool
    @State private var draggingRootID: String?
    @State private var addHover = false

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
                    if !state.normalizedQuery.isEmpty {
                        searchResults
                    } else {
                        tree
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.5)

            // Bottom add-folder bar, like Finder's sidebar footer controls
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Button { state.pickFolders() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.accentColor)
                            Text("Add Folder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .dockTooltip("Add a local folder")

                    Divider().frame(height: 20)

                    Button { state.showAddRemote = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("Add Remote")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .dockTooltip("Add a remote (SSH) folder")
                }
                .buttonStyle(ToolbarIconButtonStyle(width: nil, height: nil, glass: false))
                .fixedSize()
                .glassCapsule(hovering: addHover)
                .onHover { addHover = $0 }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(GlassPanel())
        .onChange(of: state.focusSearch) { _ in searchFocused = true }
        .sheet(item: $state.editingRemote) { spec in
            AddRemoteView(existing: spec).environmentObject(state)
        }
        .alert("Sync failed", isPresented: Binding(
            get: { state.syncAlertError != nil },
            set: { if !$0 { state.syncAlertError = nil } }
        )) {
            Button("OK") { state.syncAlertError = nil }
        } message: {
            Text(state.syncAlertError ?? "")
        }
    }

    /// The normal (unfiltered) sidebar: recents, then the folder tree.
    @ViewBuilder
    private var tree: some View {
        if !state.recentFiles.isEmpty {
            HStack {
                sectionHeader("RECENTS")
                Button("Clear") { state.clearRecents() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 12)
                    .dockTooltip("Clear recent files")
            }
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
            RootSectionView(root: root, draggingRootID: $draggingRootID)
        }
    }

    /// Filter hits as a flat list, each labelled with its folder. Flat rather than
    /// a filtered tree so the enclosing LazyVStack only builds the visible rows —
    /// the tree form expanded every root and built all of them.
    @ViewBuilder
    private var searchResults: some View {
        sectionHeader("RESULTS")
        if state.searchResults.isEmpty {
            Text("No matching files")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
        ForEach(state.searchResults) { file in
            SearchResultRow(file: file)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// One sidebar filter hit: filename over its folder location. A flat list needs
/// the location — indentation carried it in the tree, and README.md is everywhere.
struct SearchResultRow: View {
    @EnvironmentObject var state: AppState
    let file: IndexedFile
    @State private var hovering = false

    private var isSelected: Bool { state.selectedFile?.id == file.node.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Text(file.locationLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            if let badge = state.gitStatus(for: file.node.url.path) {
                Text(badge.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    .dockTooltip(badge.help)
            }
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
        .onTapGesture { state.open(file.node) }
        .contextMenu {
            if isSelected {
                Button("Close") { state.closeFile() }
            } else {
                Button("Open") { state.open(file.node) }
            }
            OpenWithMenu(state: state, url: file.node.url)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.node.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.node.url.path, forType: .string)
            }
        }
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
            if hovering {
                Button { state.removeRecent(path) } label: {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .dockTooltip("Remove from Recents")
            }
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
        .contextMenu {
            if isSelected {
                Button("Close") { state.closeFile() }
            } else {
                Button("Open") { state.openPath(path) }
            }
            OpenWithMenu(state: state, url: URL(fileURLWithPath: path))
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            Divider()
            Button("Remove from Recents") { state.removeRecent(path) }
        }
    }
}

/// A single root folder header + its filtered contents.
struct RootSectionView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var root: RootFolder
    @Binding var draggingRootID: String?
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
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
                if root.isRemote {
                    Image(systemName: "cloud")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .dockTooltip("Remote folder")
                    switch root.syncStatus {
                    case .syncing:
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    case .failed(let msg):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .dockTooltip(msg)
                    case .idle:
                        EmptyView()
                    }
                }
                Spacer(minLength: 4)
                if hovering {
                    if let spec = root.remote {
                        Button { state.editingRemote = spec } label: {
                            Image(systemName: "pencil").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .dockTooltip("Edit connection")
                        Button {
                            Task { await state.syncRemote(spec, surfaceErrors: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .dockTooltip("Re-sync")
                    }
                    Button { state.removeRoot(root) } label: {
                        Image(systemName: "xmark").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .dockTooltip("Remove folder")
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } }
            .onHover { hovering = $0 }
            .opacity(draggingRootID == root.id ? 0.4 : 1)
            .onDrag {
                draggingRootID = root.id
                return NSItemProvider(object: root.id as NSString)
            }
            .onDrop(of: [.text],
                    delegate: RootReorderDelegate(target: root, draggingRootID: $draggingRootID, state: state))
            .contextMenu {
                Button(expanded ? "Collapse" : "Expand") {
                    withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([root.url])
                }
                if let spec = root.remote {
                    Divider()
                    Button("Edit Connection…") { state.editingRemote = spec }
                    Button("Re-sync") { Task { await state.syncRemote(spec, surfaceErrors: true) } }
                }
                Divider()
                Button(root.isRemote ? "Remove Remote Folder" : "Remove Folder") {
                    state.removeRoot(root)
                }
            }

            if expanded {
                ForEach(root.children) { node in
                    FileTreeRow(node: node, depth: 1)
                }
            }
        }
        // Reveal the open file: expand the root that holds it (each directory on the
        // way down does the same, so the whole path opens).
        .onAppear { if holdsSelection { expanded = true } }
        .onChange(of: state.selectedFile?.url.path) { _ in
            if holdsSelection { withAnimation(.easeInOut(duration: 0.12)) { expanded = true } }
        }
    }

    private var holdsSelection: Bool {
        guard let path = state.selectedFile?.url.standardizedFileURL.path else { return false }
        return path.hasPrefix(root.url.standardizedFileURL.path + "/")
    }
}

/// Live-reorders roots as a dragged folder hovers over another.
struct RootReorderDelegate: DropDelegate {
    let target: RootFolder
    @Binding var draggingRootID: String?
    let state: AppState

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingRootID, dragging != target.id,
              let from = state.roots.firstIndex(where: { $0.id == dragging }),
              let to = state.roots.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            state.moveRoot(from: from, to: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingRootID = nil
        return true
    }
}
