import SwiftUI

/// Preview's toolbar icon metrics: larger and lighter than the sidebar's buttons.
private let topBarButton = ToolbarIconButtonStyle(
    width: 36, height: 32, glass: false, iconSize: 15, iconWeight: .regular
)

struct TopBar: View {
    @EnvironmentObject var state: AppState
    @FocusState private var findFocused: Bool

    var body: some View {
        barContainer
            .padding(.horizontal, 12)
            .frame(height: ChromeMetrics.topBarHeight)
            .background(
                ZStack {
                    // No surface of its own: like Preview, the bar is the window's
                    // titlebar material and only the control capsules read as glass.
                    BackgroundDrag() // transparent hit layer for window dragging
                    TrafficLightConfigurator() // centers the native window buttons in the bar
                }
            )
    }

    // Group the glass buttons so adjacent ones (e.g. back/forward) blend and
    // morph together, per Apple's Liquid Glass guidance. macOS 26 only.
    @ViewBuilder private var barContainer: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 5) { bar }
        } else {
            bar
        }
    }

    // Preview splits its toolbar into several short capsules grouped by function,
    // rather than one long one. Dividers separate segments *within* a capsule; the
    // gaps between capsules do the rest.
    private var bar: some View {
        HStack(spacing: 8) {
            // leave just enough room for the native traffic lights (pinned by
            // TrafficLightConfigurator); the sidebar toggle sits right after them.
            Color.clear.frame(width: 72, height: 1)

            Button { state.toggleSidebar() } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar (⌘\\)")
            .buttonStyle(topBarButton)
            .glassCapsule()

            // Back / forward, kept together like Finder.
            HStack(spacing: 0) {
                Button { state.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!state.canGoBack)
                    .help("Back (⌘[)")
                Button { state.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!state.canGoForward)
                    .help("Forward (⌘])")
            }
            .buttonStyle(topBarButton)
            .glassCapsule()

            breadcrumb
                .padding(.leading, 4)

            Spacer(minLength: 8)

            // Rehomed from the status bar. Both hide themselves when they have
            // nothing to report, so no capsule is drawn in the common case.
            ResolvedThreadsToggle()
            OrphanedMarksBadge()

            // View: typography + outline.
            HStack(spacing: 0) {
                typographyMenu

                if !state.toc.isEmpty {
                    Divider().frame(height: 20)
                    Button { state.setShowTOC(!state.showTOC) } label: {
                        Image(systemName: "list.bullet")
                    }
                    .help("Toggle outline (⌘⇧O)")
                }
            }
            .buttonStyle(topBarButton)
            .glassCapsule()

            // Document actions.
            HStack(spacing: 0) {
                Button { state.triggerReload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(state.selectedFile == nil)
                .help("Reload (⌘R)")

                Divider().frame(height: 20)
                Button { state.triggerExport() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(state.selectedFile == nil)
                .help("Export as PDF (⌘E)")
            }
            .buttonStyle(topBarButton)
            .glassCapsule()

            Button { state.toggleTheme() } label: {
                Image(systemName: state.theme.symbol)
            }
            .help(state.theme == .dark ? "Switch to light mode" : "Switch to dark mode")
            .buttonStyle(topBarButton)
            .glassCapsule()

            findField
        }
    }

    private var typographyMenu: some View {
        Menu {
            Picker("Theme", selection: Binding(
                get: { state.readingTheme },
                set: { state.setReadingTheme($0) }
            )) {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.inline)

            Divider()
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
                .font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 36, height: 32)
        .help("Text size & width")
    }

    /// Preview keeps search inline in the toolbar rather than behind a button.
    /// Enter finds the next match, Escape clears; ⌘G / ⇧⌘G step the matches.
    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Search", text: $state.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .frame(width: 110)
                .focused($findFocused)
                .onSubmit { state.triggerFindNext() }
                .onExitCommand { state.findQuery = "" }

            if !state.findQuery.isEmpty {
                Text(state.findCount > 0 ? "\(state.findIndex + 1)/\(state.findCount)" : "0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { state.findQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .glassCapsule()
        .disabled(state.selectedFile == nil)
        .opacity(state.selectedFile == nil ? 0.5 : 1)
        // ⌘F is a menu command; AppKit restores first responder after the menu
        // dismisses, so the focus request has to land a tick later.
        .onChange(of: state.focusFind) { _ in
            DispatchQueue.main.async { findFocused = true }
        }
    }

    /// Preview's two-line title: the document name over a line of metadata.
    /// The full path moves to the tooltip, where the breadcrumb used to be.
    @ViewBuilder private var breadcrumb: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.selectedFile?.name ?? "Reader.md")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.selectedFile == nil ? Color.secondary : Color.primary)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .modifier(RevealInFinder(file: state.selectedFile, path: crumbPath))
    }

    /// The old status bar's summary, now the title's second line.
    private var subtitle: String {
        if state.selectedFile != nil, state.wordCount > 0 {
            return "\(state.wordCount) words · \(state.readingMinutes) min read"
        }
        if state.selectedFile != nil { return " " }   // keep the title's baseline steady
        let count = state.allFiles().count
        if count == 0 { return "No markdown files" }
        return "\(count) markdown \(count == 1 ? "file" : "files")"
    }

    private var crumbPath: String? {
        guard let file = state.selectedFile else { return nil }
        guard let root = state.roots.first(where: { file.url.path.hasPrefix($0.url.path + "/") })
        else { return file.name }
        return ([root.name] + file.url.path
            .dropFirst(root.url.path.count + 1)
            .split(separator: "/")
            .map(String.init)
        ).joined(separator: " › ")
    }
}

/// Only a title backed by a real file is clickable / has a path to show.
private struct RevealInFinder: ViewModifier {
    let file: FileNode?
    let path: String?

    func body(content: Content) -> some View {
        if let file, let path {
            content
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                .help("\(path) — click to reveal in Finder")
        } else {
            content
        }
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
