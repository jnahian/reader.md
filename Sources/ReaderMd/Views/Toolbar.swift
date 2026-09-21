import SwiftUI

extension View {
    /// The window's native toolbar: navigation, the document title, view and
    /// document actions, and the in-page find field.
    func readerToolbar() -> some View { modifier(ReaderToolbar()) }
}

private extension View {
    /// The toolbar's one "this control is on" signal: accent tint, never a
    /// filled symbol variant. A swap to `.fill` can't be the convention because
    /// it isn't available for every glyph here — SF Symbols has no
    /// `plus.viewfinder.fill`, and an absent symbol renders as blank space
    /// rather than failing to build. `AnyShapeStyle` because the two branches
    /// are different concrete styles.
    func activeTint(_ active: Bool) -> some View {
        foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}


/// A topbar cluster: several controls sharing one Liquid Glass capsule, like
/// Finder's. The buttons pass `glass: false` — glass is never stacked, so the
/// capsule is the surface and each button only draws its hover fill.
///
/// One `ToolbarItem` holding an `HStack`, not a `ToolbarItemGroup`: the group
/// is what AppKit would style itself, and under a `NavigationSplitView` it
/// stopped doing that. A cluster is one item, so it still overflows into the
/// toolbar's `»` menu whole; it just can't collapse item by item the way a
/// group does.
/// One set of metrics for everything in a cluster. A `Button` gets them through
/// `ToolbarIconButtonStyle` and a `Menu` has to be handed them, so keeping the
/// numbers in two places is what let the pull-downs' hover fill drift smaller
/// than the buttons'.
private enum ClusterMetrics {
    static let width: CGFloat = 36
    static let height: CGFloat = 32
    static let iconSize: CGFloat = 15
    static let hoverFill: Double = 0.07
}

/// A pull-down inside a cluster. `.menuStyle(.button)` is what centres the glyph
/// in its cell — `.borderlessButton` reserves room for the indicator it was told
/// to hide and leaves the label sitting left of centre — but it then draws the
/// system's own bordered background, a rounded rect where every button beside it
/// is a pill. `.plain` drops that, and the cell and its hover fill are drawn here
/// instead, from the same metrics `ToolbarIconButtonStyle` gives a `Button`.
private struct ToolbarClusterMenu: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.system(size: ClusterMetrics.iconSize, weight: .regular))
            .frame(width: ClusterMetrics.width, height: ClusterMetrics.height)
            .background(Capsule().fill(
                Color.primary.opacity(hovering ? ClusterMetrics.hoverFill : 0)))
            .contentShape(Capsule())
            .onHover { hovering = $0 && isEnabled }
    }
}

private struct ToolbarCluster<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 1) { content }
            .buttonStyle(ToolbarIconButtonStyle(width: ClusterMetrics.width,
                                                height: ClusterMetrics.height,
                                                glass: false,
                                                iconSize: ClusterMetrics.iconSize,
                                                iconWeight: .regular))
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .glassCapsule()
    }
}

/// Separates two kinds of control inside one capsule (the sidebar toggle from
/// the history pair), rather than splitting them into two capsules.
private struct ToolbarClusterDivider: View {
    var body: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 3)
    }
}

private extension View {
    func toolbarClusterMenu() -> some View { modifier(ToolbarClusterMenu()) }
}

/// A ViewModifier rather than a `ToolbarContent` type so the find field's
/// `@FocusState` and the `@EnvironmentObject` live in a real view scope.
private struct ReaderToolbar: ViewModifier {
    @EnvironmentObject var state: AppState

    func body(content: Content) -> some View {
        titled(content)
            .navigationTitle(state.selectedFile?.name ?? "Reader.md")
            .navigationSubtitle(subtitle)
            .toolbar {
                // Navigation: the sidebar toggle and the history pair, one
                // capsule, the way Finder groups its own chrome.
                ToolbarItem(placement: .navigation) {
                    ToolbarCluster {
                        Button { state.toggleSidebar() } label: {
                            Image(systemName: "sidebar.left").activeTint(state.showSidebar)
                        }
                        .dockTooltip("Toggle sidebar (⌘B)")

                        ToolbarClusterDivider()

                        Button { state.goBack() } label: { Image(systemName: "chevron.left") }
                            .disabled(!state.canGoBack)
                            .dockTooltip("Back (⌘[)")
                        Button { state.goForward() } label: { Image(systemName: "chevron.right") }
                            .disabled(!state.canGoForward)
                            .dockTooltip("Forward (⌘])")
                    }
                }

                // Both hide themselves when they have nothing to report, so they
                // stay outside the capsules rather than leaving an empty one.
                ToolbarItemGroup(placement: .primaryAction) {
                    ResolvedThreadsToggle()
                    OrphanedMarksBadge()
                }

                // View: reading style + canvas width + outline + focus.
                ToolbarItem(placement: .primaryAction) {
                    ToolbarCluster {
                        readingStyleMenu
                        canvasWidthMenu

                        if !state.toc.isEmpty {
                            Button { state.setShowTOC(!state.showTOC) } label: {
                                Image(systemName: "list.bullet").activeTint(state.showTOC)
                            }
                            .dockTooltip("Toggle outline (⇧⌘B)")
                        }

                        Button { state.toggleFocusMode() } label: {
                            Image(systemName: "plus.viewfinder").activeTint(state.focusMode)
                        }
                        .dockTooltip("Focus mode (⌥⌘F)")
                    }
                }

                // Diff: hidden entirely outside a git repo, and gated on nothing
                // else. It deliberately does NOT also disable on "file has no
                // changes": that answer comes from `gitStatuses`, which is only
                // built for files under a root folder, so a file opened on its
                // own (File ▸ Open, `reader open`, Finder) would read as
                // unchanged and disable the button while ⇧⌘D and the palette —
                // both gated on diffAvailable alone — still worked. The pane
                // already says "No changes…" for itself.
                ToolbarItem(placement: .primaryAction) {
                    if state.diffAvailable {
                        ToolbarCluster {
                            Button { state.toggleDiffMode() } label: {
                                Image(systemName: "plusminus.circle").activeTint(state.diffMode)
                            }
                            .dockTooltip(state.diffMode
                                         ? "Show rendered view (⇧⌘D)" : "Show diff (⇧⌘D)")
                        }
                    }
                }

                // A popover rather than a segmented control or a pull-down: the
                // branch scopes are per repo, so the list has neither a fixed
                // width nor a bounded length. It is a capsule of its own, not
                // part of the diff cluster: its label is a branch name rather
                // than a glyph, and inside the cluster the toolbar item kept the
                // width it was given while diff mode was off, so turning diff on
                // drew the name over the toggle.
                ToolbarItem(placement: .primaryAction) {
                    if state.canShowDiff {
                        ToolbarCluster {
                            DiffScopePicker()
                                .buttonStyle(ToolbarIconButtonStyle(
                                    width: nil, height: ClusterMetrics.height,
                                    glass: false, iconSize: 12, iconWeight: .regular))
                        }
                    }
                }

                // Document actions.
                ToolbarItem(placement: .primaryAction) {
                    ToolbarCluster {
                        Button { state.triggerReload() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(state.selectedFile == nil)
                        .dockTooltip("Reload (⌘R)")

                        exportMenu

                        Button { state.toggleTheme() } label: {
                            Image(systemName: state.theme.symbol)
                        }
                        .dockTooltip(state.theme.tooltip,
                                     accessibility: state.theme.accessibilityLabel)
                    }
                }

                ToolbarItem(placement: .primaryAction) { findField }
            }
            .toolbar(state.focusToolbarHidden ? .hidden : .automatic, for: .windowToolbar)
    }

    /// The proxy icon: click the title to reveal in Finder, drag it to move the file.
    @ViewBuilder private func titled(_ content: Content) -> some View {
        if let url = state.selectedFile?.url {
            content.navigationDocument(url)
        } else {
            content
        }
    }

    /// Export and share, built like the two menus beside it. The icon stays
    /// `square.and.arrow.up` — already the share glyph.
    ///
    /// `sharing` greys the share *row*, not the menu: a disabled pull-down draws
    /// its label static, so a spinner that only shows while the control is
    /// disabled would never animate. The real re-entrancy guard is in
    /// `triggerShare()`, which also covers the File menu and the palette. Leaving
    /// the menu live during a share costs nothing — concurrent exports already
    /// work through `activeExports`.
    private var exportMenu: some View {
        Menu {
            Button("Export as PDF… (⌘E)") { state.triggerExport() }
                .disabled(!state.canExport)
            Divider()
            Button("Share PDF…") { state.triggerShare() }
                .disabled(!state.canExport || state.sharing)
            Button("Share Markdown File…") { state.triggerShareSource() }
        } label: {
            if state.sharing {
                ProgressView().controlSize(.small)
            } else {
                // Optically matched, not nominally: at the same point size this
                // glyph's ink is 11x14 against 14x17 for `arrow.clockwise` right
                // beside it, because the symbol reserves vertical room for the
                // arrow and is drawn narrow. `.large` levels the two.
                Image(systemName: "square.and.arrow.up")
                    .imageScale(.large)
                    
            }
        }
        .menuIndicator(.hidden)
        .toolbarClusterMenu()
        .background(ShareAnchor.Marker())
        // Only "a document is open" — not `canExport`. The two PDF rows gate
        // themselves on that, but sharing the markdown needs no render, so it
        // stays available in the diff pane where there is nothing to render.
        .disabled(state.selectedFile == nil)
        .dockTooltip("Export and share")
    }

    private var readingStyleMenu: some View {
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

            Section("Text Size") {
                Button("Increase Text (⌘+)") { state.adjustFontScale(0.1) }
                Button("Decrease Text (⌘−)") { state.adjustFontScale(-0.1) }
                Button("Actual Size (⌘0)") { state.resetFontScale() }
            }
        } label: {
            Image(systemName: "textformat.size")
                .activeTint(state.readingTheme != .standard)
        }
        // `activeTint` sits on the label now. It had to be on the `Menu` while
        // the pull-down was drawn by the toolbar — that took the label image as
        // a template and dropped a `foregroundStyle` set inside it — but the
        // label is rendered plainly here. (`.tint` is still not the same thing:
        // it draws a selection chip behind the glyph.)
        .menuIndicator(.hidden)
        .toolbarClusterMenu()
        .dockTooltip("Reading style")
    }

    private var canvasWidthMenu: some View {
        Menu {
            Picker("Canvas Width", selection: Binding(
                get: { state.contentWidth },
                set: { state.setContentWidth($0) }
            )) {
                ForEach(ContentWidth.allCases, id: \.self) { width in
                    Text(width.displayName).tag(width)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.left.and.right")
                .activeTint(state.contentWidth != .wide)
        }
        .menuIndicator(.hidden)
        .toolbarClusterMenu()
        .dockTooltip("Canvas width (⇧⌘\\)")
    }

    /// Search stays inline in the toolbar, like Preview. Enter finds the next
    /// match, Escape clears; the chevrons and ⌘G / ⇧⌘G (or ⌘↩ / ⇧⌘↩) step the
    /// matches. Not `.searchable`: that can't show the match count, and focusing
    /// it programmatically (⌘F) is macOS 14+.
    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            FindTextField(
                text: $state.findQuery,
                focusToken: state.focusFind,
                onSubmit: { state.triggerFindNext() },
                onPrev: { state.triggerFindPrev() },
                onCancel: { state.findQuery = "" }
            )
            .frame(width: 110, height: 18)

            if !state.findQuery.isEmpty {
                Text(state.findCount > 0 ? "\(state.findIndex + 1)/\(state.findCount)" : "0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                // Step the matches without leaving the mouse — the same actions
                // the ⌘↩ / ⇧⌘↩ and ⌘G / ⇧⌘G shortcuts fire.
                HStack(spacing: 2) {
                    Button { state.triggerFindPrev() } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .dockTooltip("Previous match (⇧⌘↩)")

                    Button { state.triggerFindNext() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .dockTooltip("Next match (⌘↩)")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                // `.plain` buttons don't dim themselves when disabled.
                .opacity(state.findCount > 0 ? 1 : 0.4)
                .disabled(state.findCount == 0)

                Button { state.findQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .dockTooltip("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassCapsule()
        .disabled(state.selectedFile == nil)
        .opacity(state.selectedFile == nil ? 0.5 : 1)
    }

    /// The old status bar's summary, now the window title's second line.
    private var subtitle: String {
        if state.selectedFile != nil, state.wordCount > 0, !state.canShowDiff {
            return "\(state.wordCount) words · \(state.readingMinutes) min read"
        }
        if state.selectedFile != nil { return "" }
        let count = state.fileCount
        if count == 0 { return "No markdown files" }
        return "\(count) markdown \(count == 1 ? "file" : "files")"
    }
}


/// SwiftUI's `@FocusState` doesn't reach into the toolbar's own hosting view, so
/// ⌘F can't focus a SwiftUI `TextField` there. An `NSTextField` we can make first
/// responder ourselves does work.
private struct FindTextField: NSViewRepresentable {
    @Binding var text: String
    /// Flipped by ⌘F; a change (not a value) is the request to focus.
    var focusToken: Bool
    var onSubmit: () -> Void
    var onPrev: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> FindField {
        let field = FindField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search"
        field.font = .systemFont(ofSize: 12.5)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: FindField, context: Context) {
        context.coordinator.parent = self
        // Reassigned every update, not captured once: the closures hold `state`,
        // and the representable is a fresh struct on each render.
        field.onNext = onSubmit
        field.onPrev = onPrev
        if field.stringValue != text { field.stringValue = text }
        // An NSViewRepresentable doesn't pick up `.disabled` on its own.
        field.isEnabled = context.environment.isEnabled

        guard context.coordinator.focusToken != focusToken else { return }
        context.coordinator.focusToken = focusToken
        // ⌘F is a menu command; AppKit restores first responder after the menu
        // dismisses, so the focus request has to land a tick later.
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindTextField
        var focusToken: Bool

        init(_ parent: FindTextField) {
            self.parent = parent
            self.focusToken = parent.focusToken
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}

/// Steps matches on ⌘↩ / ⇧⌘↩ while the field is being edited — the pair the
/// chevron tooltips and SHORTCUTS.md advertise.
///
/// It has to be `performKeyEquivalent`, not the delegate's `doCommandBySelector`
/// above: a Command-modified Return isn't in AppKit's key bindings, so the field
/// editor never turns it into a selector, and plain ↩ (which is bound, to
/// `insertNewline:`) is the only Return the delegate ever sees.
final class FindField: NSTextField {
    var onNext: () -> Void = {}
    var onPrev: () -> Void = {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Gated on being the focused field: performKeyEquivalent walks every
        // view in the window, so an unfocused search box would otherwise
        // swallow ⌘↩ from wherever the user actually is.
        guard event.keyCode == 36, currentEditor() != nil,
              window?.firstResponder === currentEditor()
        else { return super.performKeyEquivalent(with: event) }

        switch event.modifierFlags.intersection(.deviceIndependentFlagsMask) {
        case .command:          onNext(); return true
        case [.command, .shift]: onPrev(); return true
        default:                return super.performKeyEquivalent(with: event)
        }
    }
}
