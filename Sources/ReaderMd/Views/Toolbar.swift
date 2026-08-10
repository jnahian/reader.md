import SwiftUI

extension View {
    /// The window's native toolbar: navigation, the document title, view and
    /// document actions, and the in-page find field.
    func readerToolbar() -> some View { modifier(ReaderToolbar()) }
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
                ToolbarItem(placement: .navigation) {
                    Button { state.toggleSidebar() } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .dockTooltip("Toggle sidebar (⌘B)")
                }

                // Back / forward, kept together like Finder.
                ToolbarItemGroup(placement: .navigation) {
                    Button { state.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!state.canGoBack)
                        .dockTooltip("Back (⌘[)")
                    Button { state.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!state.canGoForward)
                        .dockTooltip("Forward (⌘])")
                }

                // Both hide themselves when they have nothing to report.
                ToolbarItemGroup(placement: .primaryAction) {
                    ResolvedThreadsToggle()
                    OrphanedMarksBadge()
                }

                // View: reading style + canvas width + outline.
                ToolbarItemGroup(placement: .primaryAction) {
                    readingStyleMenu
                    canvasWidthMenu

                    if !state.toc.isEmpty {
                        Button { state.setShowTOC(!state.showTOC) } label: {
                            Image(systemName: "list.bullet")
                        }
                        .dockTooltip("Toggle outline (⇧⌘B)")
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
                ToolbarItemGroup(placement: .primaryAction) {
                    if state.diffAvailable {
                        Button { state.toggleDiffMode() } label: {
                            Image(systemName: state.diffMode
                                  ? "plusminus.circle.fill" : "plusminus.circle")
                        }
                        .dockTooltip(state.diffMode
                                     ? "Show rendered view (⇧⌘D)" : "Show diff (⇧⌘D)")

                        // A popover rather than a segmented control or a
                        // pull-down: the branch scopes are per repo, so the list
                        // has neither a fixed width nor a bounded length.
                        if state.canShowDiff {
                            DiffScopePicker()
                        }
                    }
                }

                // Document actions.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { state.triggerReload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(state.selectedFile == nil)
                    .dockTooltip("Reload (⌘R)")

                    Button { state.triggerExport() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(state.selectedFile == nil || state.canShowDiff)
                    .dockTooltip("Export as PDF (⌘E)")

                    Button { state.toggleTheme() } label: {
                        Image(systemName: state.theme.symbol)
                    }
                    .dockTooltip(state.theme.tooltip,
                                 accessibility: state.theme.accessibilityLabel)
                }

                ToolbarItem(placement: .primaryAction) { findField }
            }
    }

    /// The proxy icon: click the title to reveal in Finder, drag it to move the file.
    @ViewBuilder private func titled(_ content: Content) -> some View {
        if let url = state.selectedFile?.url {
            content.navigationDocument(url)
        } else {
            content
        }
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
        }
        .menuIndicator(.hidden)
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
        }
        .menuIndicator(.hidden)
        .dockTooltip("Canvas width (⇧⌘\\)")
    }

    /// Search stays inline in the toolbar, like Preview. Enter finds the next
    /// match, Escape clears; the chevrons and ⌘G / ⇧⌘G (or ⌘↩ / ⇧⌘↩) step the
    /// matches. Not `.searchable`: that can't show the match count, and focusing
    /// it programmatically (⌘F) is macOS 14+.
    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            FindTextField(
                text: $state.findQuery,
                focusToken: state.focusFind,
                onSubmit: { state.triggerFindNext() },
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
        .padding(.horizontal, 10)
        .frame(height: 26)
        .modifier(FindFieldSurface())
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

/// The native toolbar already gives its items a glass surface on macOS 26 — only
/// the pre-26 toolbar needs a capsule of its own, or the field reads as bare text.
private struct FindFieldSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content.glassCapsule()
        }
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
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search"
        field.font = .systemFont(ofSize: 12.5)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
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
