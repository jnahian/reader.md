import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var dragStartWidth: Double?
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar()
                ReadingProgressBar()
                Divider()
                contentRow
            }

            if state.showQuickOpen {
                QuickOpenView()
                    .transition(.opacity)
                    .zIndex(2)
            }

            if showDropOverlay {
                DropTargetOverlay()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        // Extend our custom topbar all the way to the top of the window, replacing
        // the default titlebar entirely.
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeInOut(duration: 0.15), value: state.showSidebar)
        .animation(.easeInOut(duration: 0.15), value: state.showTOC)
        .animation(.easeInOut(duration: 0.12), value: state.showQuickOpen)
        .animation(.easeInOut(duration: 0.12), value: showDropOverlay)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
    }

    private var contentRow: some View {
        HStack(spacing: 0) {
            if state.showSidebar {
                SidebarView()
                    .frame(width: CGFloat(state.sidebarWidth))
                resizeHandle
            }

            ZStack(alignment: .topTrailing) {
                if state.selectedFile == nil {
                    EmptyStateView()
                }
                MarkdownWebView()
                    .opacity(state.selectedFile == nil ? 0 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.showTOC && !state.toc.isEmpty {
                Divider()
                TOCView()
                    .frame(width: 240)
            }
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let start = dragStartWidth ?? state.sidebarWidth
                                if dragStartWidth == nil { dragStartWidth = start }
                                state.sidebarWidth = min(460, max(180, start + Double(value.translation.width)))
                            }
                            .onEnded { _ in
                                state.setSidebarWidth(state.sidebarWidth)
                                dragStartWidth = nil
                            }
                    )
            )
    }

    /// Two independent drop paths report targeting: SwiftUI's `.onDrop` for the chrome,
    /// and DropWebView for the content pane (it consumes the drag first). They are kept
    /// as separate flags and OR-ed — dragging from the sidebar onto the content pane
    /// fires one's exit and the other's enter in an order neither controls, so a single
    /// shared flag would flicker off mid-drag.
    private var showDropOverlay: Bool { dropTargeted || state.webDropTargeted }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in state.openDropped(url) }
            }
        }
        return true
    }
}

/// Shown while a valid file drag is over the window. Drop already worked; without
/// this there was no sign of it, so people assumed it wasn't supported.
struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.28)

            VStack(spacing: 12) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 34, weight: .light))
                Text("Drop to open")
                    .font(.system(size: 17, weight: .semibold))
                Text("A markdown file, or a folder to add")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .background(GlassPanel(cornerRadius: 16, material: .hudWindow))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            )
        }
        .ignoresSafeArea()
        // Never intercept the drag this overlay exists to advertise.
        .allowsHitTesting(false)
    }
}

/// Thin accent bar under the topbar reflecting read position.
struct ReadingProgressBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.clear
                if state.selectedFile != nil {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(state.scrollProgress))
                }
            }
        }
        .frame(height: 2)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var state: AppState

    private let hints: [(String, String, String)] = [
        ("doc.text", "Open a file", "⌘O"),
        ("folder.badge.plus", "Add a folder", ""),
        ("magnifyingglass", "Quick-open a file", "⌘P"),
        ("sidebar.left", "Filter files in the sidebar", "⇧⌘F"),
        ("arrow.down.doc", "…or drag a file or folder onto the window", ""),
    ]

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 7) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Reader.md")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("A local markdown reader")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 11) {
                ForEach(hints, id: \.1) { icon, label, shortcut in
                    HStack(spacing: 11) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        if !shortcut.isEmpty {
                            Text(shortcut)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(Color.primary.opacity(0.07))
                                )
                        }
                    }
                }
            }
            .frame(width: 320)
            .padding(.vertical, 17)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
