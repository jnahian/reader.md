import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var dropTargeted = false
    @State private var topInset: CGFloat = 0
    @State private var documentWindow: NSWindow?

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 260, max: 460)
                // The split view injects its own toggle; ours (Toolbar.swift)
                // carries the tooltip and the accent-tint "on" state, so the
                // system one goes. macOS 14+ only — on 13 there are two.
                .removingSidebarToggle()
        } detail: {
            VStack(spacing: 0) {
                if !state.canShowDiff {
                    ReadingProgressBar()
                }
                detailRow
            }
            .readerToolbar()
            .hidingToolbarBackground()
        }
        .navigationSplitViewStyle(.balanced)
        // Overlays sit on the split view, not in the detail column, so they
        // cover the sidebar too — quick-open is a window-wide palette.
        .overlay {
            if state.showQuickOpen {
                QuickOpenView().transition(.opacity)
            }
        }
        .overlay {
            if showDropOverlay {
                DropTargetOverlay().transition(.opacity)
            }
        }
        .background(findStepShortcuts)
        .background(WindowAccessor {
            state.setDocumentWindow($0)
            extendContentUnderTitlebar($0)
            documentWindow = $0
            measureTitlebar()
        })
        // The titlebar's height is what the pane draws under, and it changes
        // when focus mode hides the toolbar or takes the window fullscreen.
        .onChange(of: state.focusToolbarHidden) { _ in measureTitlebar() }
        .onChange(of: state.focusMode) { _ in measureTitlebar() }
        // Entering and leaving fullscreen is animated, so the state change above
        // measures mid-transition; these fire once it has settled.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didEnterFullScreenNotification)) { _ in measureTitlebar() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didExitFullScreenNotification)) { _ in measureTitlebar() }
        .animation(.easeInOut(duration: 0.15), value: state.showTOC)
        .animation(.easeInOut(duration: 0.12), value: state.showQuickOpen)
        .animation(.easeInOut(duration: 0.12), value: showDropOverlay)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: handleDrop)
        .sheet(isPresented: $state.showAddRemote, onDismiss: { state.pendingRemote = nil }) {
            // Keyed on the pending remote so a second `reader remote …` arriving while
            // the sheet is already open re-seeds the fields. Without the id, SwiftUI
            // keeps the first presentation's @State and the new prefill is dropped.
            AddRemoteView(prefill: state.pendingRemote)
                .environmentObject(state)
                .id(state.pendingRemote?.id)
        }
    }

    /// `showSidebar` stays the source of truth — dragging the split view shut
    /// has to run through `toggleSidebar()` so the preference is saved and the
    /// focus-mode stash stays in step with it.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { state.showSidebar ? .all : .detailOnly },
            set: { visibility in
                let shown = visibility != .detailOnly
                if shown != state.showSidebar { state.toggleSidebar() }
            }
        )
    }


    /// Lets the window's content view cover the titlebar, so the content pane
    /// can draw behind the toolbar and the toolbar's material has something to
    /// blur — Finder's arrangement. Without this the split view lays the detail
    /// column out below the titlebar and SwiftUI reports no top safe area at
    /// all, so `.ignoresSafeArea` has nothing to ignore.
    /// The pane covers the whole window now, so the page has to be told how much
    /// of its top the toolbar sits over. AppKit is the only source for it: under
    /// a full-height split item SwiftUI reports no top safe area at all.
    /// Deferred a tick because the toolbar has not resized yet when the state
    /// that hides it changes.
    private func measureTitlebar() {
        DispatchQueue.main.async {
            guard let window = documentWindow, let content = window.contentView else { return }
            topInset = max(0, content.frame.height - window.contentLayoutRect.height)
        }
    }

    private func extendContentUnderTitlebar(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // `allowsFullHeightLayout` is the split view item's own opt-in, and the
        // only way to it: NavigationSplitView builds the controller and doesn't
        // surface the flag. AppKit already grants it to the sidebar, which is
        // why the traffic lights sit on it; the detail item has to ask.
        guard let root = window.contentViewController,
              let split = firstSplitViewController(root) else { return }
        for item in split.splitViewItems { item.allowsFullHeightLayout = true }
    }

    private func firstSplitViewController(_ vc: NSViewController) -> NSSplitViewController? {
        if let split = vc as? NSSplitViewController { return split }
        for child in vc.children {
            if let split = firstSplitViewController(child) { return split }
        }
        return nil
    }

    /// ⌘↩ / ⇧⌘↩ as aliases for Find Next / Find Previous. They can't live in the
    /// Find menu beside ⌘G / ⇧⌘G — a menu item carries one key equivalent, and a
    /// second "Find Next" row reads as a bug — so they ride on invisible buttons
    /// in the window instead; the find field's chevrons are what advertise them.
    /// `.opacity(0)` rather than `.hidden()`: a hidden view stops matching key
    /// equivalents. Sitting in `.background`, they're covered by opaque content,
    /// so they never take a click either.
    private var findStepShortcuts: some View {
        ZStack {
            Button("Find Next") { state.triggerFindNext() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Find Previous") { state.triggerFindPrev() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
        }
        .disabled(state.findQuery.isEmpty)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var detailRow: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if state.selectedFile == nil {
                    EmptyStateView()
                }
                // Only the web view reaches under the titlebar, so the text
                // scrolls behind the toolbar's blur the way Finder's list does.
                // Everything else in this stack — the close button, the empty
                // state, the outline beside it — stays inside the safe area.
                MarkdownWebView(topInset: topInset)
                    .opacity(state.selectedFile == nil ? 0 : 1)
                    // Gated on there actually being a titlebar to draw under.
                    // Focus mode hides the toolbar and goes fullscreen, and
                    // without the gate the page then runs up under the notch.
                    .ignoresSafeArea(.container, edges: topInset > 0 ? .top : [])

                if state.selectedFile != nil && !state.diagramFullscreen && !state.focusMode {
                    CloseDocButton()
                        .padding(.top, 10)
                        .padding(.trailing, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if state.showTOC && !state.toc.isEmpty {
                Divider()
                TOCView()
                    .frame(width: 240)
            }
        }
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

/// Floating × over the open document — the discoverable form of ⌘W / File → Close.
struct CloseDocButton: View {
    @EnvironmentObject var state: AppState
    @State private var hovering = false

    var body: some View {
        Button { state.closeFile() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(GlassPanel(cornerRadius: 12, material: .hudWindow))
                .overlay(Circle().stroke(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.45)
        .onHover { hovering = $0 }
        .dockTooltip("Close file (⌘W)")
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
    @EnvironmentObject var reading: ReadingState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.clear
                if state.selectedFile != nil {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(reading.progress))
                }
            }
        }
        .frame(height: 2)
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var state: AppState

    private struct Hint: Identifiable {
        let id = UUID()
        let icon: String
        let label: String
        let shortcut: String
        let action: (() -> Void)?   // nil = not an action, just a hint
    }

    private var hints: [Hint] {
        [
            Hint(icon: "doc.text", label: "Open a file", shortcut: "⌘O", action: { state.pickFile() }),
            Hint(icon: "folder.badge.plus", label: "Add a folder", shortcut: "", action: { state.pickFolders() }),
            Hint(icon: "magnifyingglass", label: "Quick-open a file", shortcut: "⌘P", action: { state.showQuickOpen = true }),
            Hint(icon: "sidebar.left", label: "Filter files in the sidebar", shortcut: "⇧⌘F", action: {
                if !state.showSidebar { state.toggleSidebar() }
                state.focusSearch.toggle()
            }),
            Hint(icon: "arrow.down.doc", label: "…or drag a file or folder onto the window", shortcut: "", action: nil),
        ]
    }

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

            VStack(alignment: .leading, spacing: 3) {
                ForEach(hints) { hint in
                    HintRow(hint: hint)
                }
            }
            .frame(width: 320)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// One line of the empty state. The actionable ones run their action on click
    /// and light up on hover; the drag hint is inert.
    private struct HintRow: View {
        let hint: Hint
        @State private var hovering = false

        /// Only the actionable hints become controls; the closing "…or drag a
        /// file" line is prose, and a focus stop on it would be a dead end.
        @ViewBuilder var body: some View {
            if let action = hint.action {
                row.rowButton(action)
            } else {
                row
            }
        }

        private var row: some View {
            HStack(spacing: 11) {
                Image(systemName: hint.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(hint.label)
                    .font(.system(size: 13))
                    .foregroundStyle(hint.action != nil && hovering ? .primary : .secondary)
                Spacer(minLength: 12)
                if !hint.shortcut.isEmpty {
                    Text(hint.shortcut)
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
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering && hint.action != nil ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                guard hint.action != nil else { return }
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}


private extension View {
    /// The toolbar draws an opaque background over the content that now scrolls
    /// beneath it. `.toolbarBackgroundVisibility` is the macOS 15+ spelling;
    /// `.toolbarBackground` is the 13+ one, and does nothing on this window.
    @ViewBuilder func hidingToolbarBackground() -> some View {
        if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            toolbarBackground(.hidden, for: .windowToolbar)
        }
    }

    /// `.toolbar(removing:)` is macOS 14+; on 13 the split view's own sidebar
    /// toggle stays, beside ours.
    @ViewBuilder func removingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
