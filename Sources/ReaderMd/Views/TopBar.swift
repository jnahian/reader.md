import SwiftUI

struct TopBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            // leave just enough room for the native traffic lights (pinned by
            // TrafficLightConfigurator); the sidebar toggle sits right after them.
            Color.clear.frame(width: 72, height: 1)

            // Sidebar toggle
            Button { state.toggleSidebar() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar (⌘\\)")

            // Back / forward, grouped like Finder
            HStack(spacing: 2) {
                Button { state.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!state.canGoBack)
                    .help("Back (⌘[)")
                Button { state.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!state.canGoForward)
                    .help("Forward (⌘])")
            }
            .padding(.leading, 2)

            breadcrumb
                .padding(.leading, 4)

            Spacer(minLength: 8)

            // Typography controls
            Menu {
                Button("Increase Text  ⌘+") { state.adjustFontScale(0.1) }
                Button("Decrease Text  ⌘−") { state.adjustFontScale(-0.1) }
                Button("Actual Size  ⌘0") { state.resetFontScale() }
                Divider()
                Toggle("Wide Reading Column", isOn: Binding(
                    get: { state.wideReading },
                    set: { _ in state.toggleWideReading() }
                ))
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30, height: 24)
            .help("Text size & width")

            if !state.toc.isEmpty {
                Button { state.setShowTOC(!state.showTOC) } label: {
                    Image(systemName: "list.bullet")
                }
                .help("Toggle outline (⌘⇧O)")
            }

            Button { state.toggleTheme() } label: {
                Image(systemName: state.theme.symbol)
            }
            .help(state.theme == .dark ? "Switch to light mode" : "Switch to dark mode")
        }
        .buttonStyle(ToolbarIconButtonStyle())
        .padding(.horizontal, 12)
        .frame(height: ChromeMetrics.topBarHeight)
        .background(
            ZStack {
                GlassPanel()
                BackgroundDrag() // transparent hit layer for window dragging
                TrafficLightConfigurator() // centers the native window buttons in the bar
            }
        )
    }

    @ViewBuilder private var breadcrumb: some View {
        if let file = state.selectedFile, let crumbs = crumbComponents {
            HStack(spacing: 3) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { idx, part in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(part)
                        .font(.system(size: 12.5, weight: idx == crumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(idx == crumbs.count - 1 ? Color.primary : Color.secondary)
                        .lineLimit(1)
                }
            }
            .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            .help("Reveal in Finder")
        } else {
            Text("Reader.md")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var crumbComponents: [String]? {
        guard let file = state.selectedFile else { return nil }
        if let root = state.roots.first(where: { file.url.path.hasPrefix($0.url.path + "/") }) {
            var parts = [root.name]
            let rel = file.url.path
                .dropFirst(root.url.path.count + 1)
                .split(separator: "/")
                .map(String.init)
            parts.append(contentsOf: rel)
            return parts
        }
        return [file.name]
    }
}

/// A transparent view that lets the user drag the window from the topbar.
struct BackgroundDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
