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
                    .help("Toggle sidebar (⌘\\)")
                }

                // Back / forward, kept together like Finder.
                ToolbarItemGroup(placement: .navigation) {
                    Button { state.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!state.canGoBack)
                        .help("Back (⌘[)")
                    Button { state.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!state.canGoForward)
                        .help("Forward (⌘])")
                }

                // Both hide themselves when they have nothing to report.
                ToolbarItemGroup(placement: .primaryAction) {
                    ResolvedThreadsToggle()
                    OrphanedMarksBadge()
                }

                // View: typography + outline.
                ToolbarItemGroup(placement: .primaryAction) {
                    typographyMenu

                    if !state.toc.isEmpty {
                        Button { state.setShowTOC(!state.showTOC) } label: {
                            Image(systemName: "list.bullet")
                        }
                        .help("Toggle outline (⌘⇧O)")
                    }
                }

                // Document actions.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { state.triggerReload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(state.selectedFile == nil)
                    .help("Reload (⌘R)")

                    Button { state.triggerExport() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(state.selectedFile == nil)
                    .help("Export as PDF (⌘E)")

                    Button { state.toggleTheme() } label: {
                        Image(systemName: state.theme.symbol)
                    }
                    .help(state.theme == .dark ? "Switch to light mode" : "Switch to dark mode")
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
            Picker("Column Width", selection: Binding(
                get: { state.contentWidth },
                set: { state.setContentWidth($0) }
            )) {
                ForEach(ContentWidth.allCases, id: \.self) { width in
                    Text(width.displayName).tag(width)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "textformat.size")
        }
        .menuIndicator(.hidden)
        .help("Text size & width")
    }

    /// Search stays inline in the toolbar, like Preview. Enter finds the next
    /// match, Escape clears; ⌘G / ⇧⌘G step the matches. Not `.searchable`: that
    /// can't show the match count, and focusing it programmatically (⌘F) is macOS 14+.
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
        .frame(height: 26)
        .modifier(FindFieldSurface())
        .disabled(state.selectedFile == nil)
        .opacity(state.selectedFile == nil ? 0.5 : 1)
    }

    /// The old status bar's summary, now the window title's second line.
    private var subtitle: String {
        if state.selectedFile != nil, state.wordCount > 0 {
            return "\(state.wordCount) words · \(state.readingMinutes) min read"
        }
        if state.selectedFile != nil { return "" }
        let count = state.allFiles().count
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
