import SwiftUI
import AppKit

/// One row in the file tree — a directory (expandable) or a markdown file.
struct FileTreeRow: View {
    @EnvironmentObject var state: AppState
    let node: FileNode
    let depth: Int
    let query: String

    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        if node.isDirectory {
            directoryRow
        } else {
            fileRow
        }
    }

    private var isSearching: Bool { !query.isEmpty }
    private var isSelected: Bool { state.selectedFile?.id == node.id }

    private func iconColor(selected: Bool) -> Color {
        if selected { return .white }
        return node.isDirectory ? .accentColor : .secondary
    }

    private var directoryRow: some View {
        VStack(alignment: .leading, spacing: 1) {
            row(icon: "folder.fill", chevron: true, selected: false)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } }
                .contextMenu {
                    Button(expanded ? "Collapse" : "Expand") {
                        withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                    }
                    Button("Reveal in Finder") { revealInFinder() }
                    Button("Copy Path") { copyPath() }
                }

            if expanded || isSearching {
                ForEach(node.children.filter { $0.matches(query) }) { child in
                    FileTreeRow(node: child, depth: depth + 1, query: query)
                }
            }
        }
        // Expand on the way to the open file, so opening one (⌘P, Recents, a link)
        // reveals it in the tree rather than leaving it hidden in a collapsed folder.
        .onAppear { if holdsSelection { expanded = true } }
        .onChange(of: state.selectedFile?.url.path) { _ in
            if holdsSelection { withAnimation(.easeInOut(duration: 0.12)) { expanded = true } }
        }
    }

    private var holdsSelection: Bool {
        guard node.isDirectory,
              let path = state.selectedFile?.url.standardizedFileURL.path else { return false }
        return path.hasPrefix(node.url.standardizedFileURL.path + "/")
    }

    private var fileRow: some View {
        row(icon: "doc.text", chevron: false, selected: isSelected)
            .contentShape(Rectangle())
            .onTapGesture { state.open(node) }
            .contextMenu {
                if isSelected {
                    Button("Close") { state.closeFile() }
                } else {
                    Button("Open") { state.open(node) }
                }
                Button("Reveal in Finder") { revealInFinder() }
                Button("Copy Path") { copyPath() }
            }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    private func row(icon: String, chevron: Bool, selected: Bool) -> some View {
        HStack(spacing: 6) {
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            } else {
                Color.clear.frame(width: 9)
            }
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor(selected: selected))
            Text(node.name)
                .font(.system(size: 13))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 14 + 10)
        .padding(.trailing, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor
                      : (hovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
