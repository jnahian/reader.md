import SwiftUI
import AppKit

@main
struct ReaderMdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    // Auto-update via Sparkle. See Models/Updater.swift for why it's wrapped
    // rather than an SPUStandardUpdaterController wired straight to the menu.
    @StateObject private var updater = Updater()

    var body: some Scene {
        WindowGroup("Reader.md") {
            ContentView()
                .environmentObject(state)
                .environmentObject(state.reading)
                .frame(minWidth: 720, minHeight: 460)
                .preferredColorScheme(state.colorScheme)
                .onOpenURL { url in
                    if url.isFileURL {
                        // Folders become roots; files open. Treating every file URL as
                        // a document blanked the pane for `open -a Reader.md.app <dir>`
                        // and left folder paths in Recents. No extension filter here —
                        // unlike `readermd://open`, this URL is user-initiated.
                        state.openPath(url.path)
                        return
                    }
                    switch ReaderURL.action(for: url) {
                    case .open(let path, let diff):
                        // Before the open, so the file's first refreshDiff already
                        // computes the diff. Sticky, exactly like the toolbar toggle.
                        if diff, !state.diffMode { state.toggleDiffMode() }
                        // openDropped does the routing (folder -> root, markdown -> open)
                        // AND rejects non-markdown files — which is what keeps a hostile
                        // `readermd://open?path=/etc/passwd` from rendering.
                        state.openDropped(URL(fileURLWithPath: path))
                    case .addRemote(let spec):
                        // Never sync straight from a URL: rsync-over-ssh needs a human.
                        state.pendingRemote = spec
                        state.showAddRemote = true
                    case .remove(let token):
                        state.removeRoot(matching: token)
                    case nil:
                        break
                    }
                }
                .onAppear {
                    appDelegate.state = state
                    state.checkWhatsNew()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Staging a file doesn't touch the working tree, and .git is
                    // in ignoredDirs — so FSEvents never fires for it. Coming back
                    // to the window is the signal that the index may have moved.
                    state.refreshDiff()
                    state.refreshGitStatus()
                }
                // Without this, SwiftUI answers every incoming readermd:// URL by
                // opening a *second* window instead of routing it to the existing one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Reader.md") { showAboutPanel() }
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.hasFeed)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open File…") { state.pickFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Add Folder…") { state.pickFolders() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Add Remote Folder…") {
                    // nil prefill = a blank sheet. A prefill only ever arrives from a
                    // `readermd://add-remote` URL, and the menu isn't one.
                    state.pendingRemote = nil
                    state.showAddRemote = true
                }
                .keyboardShortcut("a", modifiers: [.command, .option])
                Button("Quick Open…") { state.showQuickOpen = true }
                    .keyboardShortcut("p", modifiers: .command)
                Button(state.favoriteMenuTitle) { state.toggleFavoriteCurrentFile() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(!state.canFavoriteCurrentFile)
                Divider()
                Button(state.openInEditorTitle) {
                    if let url = state.selectedFile?.url { state.openInEditor(url) }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!state.canOpenInEditor)
                Button("Set Default Editor…") { state.pickDefaultEditor() }
                Button("Export as PDF…") { state.triggerExport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!state.canExport)
                // No shortcut: nothing obvious is free near ⌘E (⇧⌘E is the
                // external editor), and an action whose result is a picker isn't
                // keystroke-worthy.
                Button("Share PDF…") { state.triggerShare() }
                    .disabled(!state.canExport || state.sharing)
                Button("Share Markdown File…") { state.triggerShareSource() }
                    .disabled(state.selectedFile == nil)
                Button("Reload") { state.triggerReload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.selectedFile == nil)
                Divider()
                Button("Install reader Command Line Tool…") { InstallCLI.run() }
            }

            CommandMenu("Find") {
                Button("Find in Page") {
                    state.revealToolbarForFind()
                    state.focusFind.toggle()
                }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(state.selectedFile == nil)
                Button("Find Next") { state.triggerFindNext() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(state.findQuery.isEmpty)
                Button("Find Previous") { state.triggerFindPrev() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(state.findQuery.isEmpty)
                Divider()
                Button("Filter Files") { state.focusSearch.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") { state.toggleSidebar() }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Toggle Outline") { state.setShowTOC(!state.showTOC) }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Focus Mode") { state.toggleFocusMode() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                Button("Toggle Diff") { state.toggleDiffMode() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(!state.diffAvailable)
                Divider()
                Button("Increase Text") { state.adjustFontScale(0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Text") { state.adjustFontScale(-0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { state.resetFontScale() }
                    .keyboardShortcut("0", modifiers: .command)
                Picker("Canvas Width", selection: Binding(
                    get: { state.contentWidth },
                    set: { state.setContentWidth($0) }
                )) {
                    ForEach(ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
                Button("Cycle Canvas Width") { state.cycleContentWidth() }
                    .keyboardShortcut("\\", modifiers: [.command, .shift])
                Divider()
            }

            CommandMenu("Go") {
                Button("Back") { state.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!state.canGoBack)
                Button("Forward") { state.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!state.canGoForward)
            }

            CommandGroup(replacing: .help) {
                Button("Reader.md FAQ") { state.openBundledDoc("FAQ") }
                Button("Keyboard Shortcuts") { state.openBundledDoc("SHORTCUTS") }
                    .keyboardShortcut("/", modifiers: .command)
                Button("Release Notes") { state.openBundledDoc("CHANGELOG") }
                Divider()
                Button("Reader.md Website") { NSWorkspace.shared.open(Links.home) }
                Button("Documentation") { NSWorkspace.shared.open(Links.docs) }
                Button("Report an Issue…") { NSWorkspace.shared.open(Links.issues) }
                Button("View on GitHub") { NSWorkspace.shared.open(Links.repo) }
            }
        }

        // `SwiftUI.Settings`, qualified: Models/Settings.swift declares a
        // module-scope `enum Settings` that shadows the scene, and a module
        // declaration beats an imported one.
        //
        // The environment object and color scheme are not inherited from
        // ContentView — a Settings scene is a sibling, not a child.
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
        }
    }
}

/// The addresses the app points at, in one place: the Help menu and the About
/// panel both offer them, and a URL typed twice is a URL that goes stale once.
private enum Links {
    static let home = URL(string: "https://reader-md.jnahian.me")!
    static let docs = URL(string: "https://reader-md.jnahian.me/docs")!
    static let issues = URL(string: "https://github.com/jnahian/reader.md/issues/new")!
    static let repo = URL(string: "https://github.com/jnahian/reader.md")!
}

// ponytail: fallback version for `swift run` (no Info.plist); keep in sync with make-app.sh.
private func showAboutPanel() {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "1.19.1"
    let build = info?["CFBundleVersion"] as? String ?? "dev"
    let center = NSMutableParagraphStyle()
    center.alignment = .center
    let credits = NSMutableAttributedString(
        string: "A native macOS markdown viewer.\nMermaid & LaTeX, live reload, PDF export.\n\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: center,
        ])
    // The standard panel renders credits in a text view, so `.link` runs are
    // live — clicking one opens it, no button needed.
    for (index, link) in [("Website", Links.home), ("Docs", Links.docs),
                          ("Report an Issue", Links.issues)].enumerated() {
        if index > 0 {
            credits.append(NSAttributedString(
                string: "  ·  ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: center,
                ]))
        }
        credits.append(NSAttributedString(
            string: link.0,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: link.1,
                .paragraphStyle: center,
            ]))
    }
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationName: "Reader.md",
        .applicationVersion: version,
        .version: build,
        .credits: credits,
    ])
    NSApp.activate(ignoringOtherApps: true)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Last launch's shared PDFs. Not cleaned up when a share finishes: an
        // AirDrop transfer keeps reading the file after the picker closes, so
        // the only moment it is certainly safe to delete is before this launch
        // has staged or opened anything.
        ShareTemp.purge()
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.resources.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
        NSApp.activate(ignoringOtherApps: true)

        // ⌘W should close the open document, not the window — closing the only window
        // quits the app, which is a surprising way to lose your place. Intercepting the
        // key event rather than retargeting the File > Close item, because SwiftUI
        // rebuilds that menu whenever a command's `.disabled` state changes (opening a
        // file does exactly that) and the rebuild puts `performClose:` right back.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "w",
                  // A sheet or the quit alert is already up: leave ⌘W alone, or repeat
                  // presses stack a second alert on top of the first.
                  NSApp.modalWindow == nil, NSApp.keyWindow?.sheets.isEmpty ?? true,
                  let self,
                  // Only the document window closes documents. Settings (and any
                  // future window) gets AppKit's performClose.
                  MainActor.assumeIsolated({ self.shouldCloseDocument })
            else { return event }
            // Deferred, not called inline: the quit path runs a modal alert, and
            // spinning a modal loop from inside sendEvent() swallows it silently.
            DispatchQueue.main.async { self.closeFileOrQuit(nil) }
            return nil
        }
        // Return activates whatever control has focus. Installed here, beside the
        // ⌘W monitor, so the two have one fixed order and one lifetime.
        ReturnKeyMonitor.install()

        // The menu item itself is rebuilt constantly, so re-point it each time the user
        // pulls the menu bar down — otherwise clicking Close would still quit.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retargetCloseItem() }
        }
    }

    /// Whether ⌘W — from the key monitor, the menu item, or its key equivalent —
    /// means "close the document" rather than "close the key window".
    ///
    /// A nil `documentWindow` reads two ways, so it's split on whether the tag
    /// ever landed. Before the first tag it's the tick between launch and
    /// ContentView's first update, when the document window is the only window
    /// there is — intercept, because letting `performClose` through would close
    /// it, and closing the last window quits the app. After a tag, nil means
    /// the document window is gone, so whatever is key now (Settings) owns ⌘W.
    @MainActor private var shouldCloseDocument: Bool {
        guard let state else { return true }
        guard let doc = state.documentWindow else { return !state.documentWindowWasTagged }
        return NSApp.keyWindow === doc
    }

    @MainActor private func retargetCloseItem() {
        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        guard let close = items.first(where: {
            $0.action == #selector(NSWindow.performClose(_:))
                || $0.action == #selector(closeFileOrQuit(_:))
        }) else { return }

        // Restore, don't just skip: the retarget below is a persistent mutation,
        // so leaving it in place while Settings is key would close the document
        // from the menu — the bug the key-monitor guard fixes for ⌘W.
        guard shouldCloseDocument else {
            close.target = nil
            close.action = #selector(NSWindow.performClose(_:))
            return
        }
        // Target is `self`, not nil: left to the responder chain the item validates as
        // disabled and the menu entry greys out.
        close.target = self
        close.action = #selector(closeFileOrQuit(_:))
    }

    @MainActor @objc func closeFileOrQuit(_ sender: Any?) {
        // The retarget above only refreshes when a menu opens, so the item can
        // still point here while another window is key: open Settings *from the
        // menu bar* and the retarget happens while the document is key, then
        // Settings takes over and ⌘W matches the stale key equivalent. Nothing
        // validates it away (there's no validateMenuItem), so re-check here and
        // do what ⌘W means everywhere else — close the key window.
        guard shouldCloseDocument else {
            NSApp.keyWindow?.performClose(sender)
            return
        }
        if let state, state.selectedFile != nil {
            state.closeFile()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Quit Reader.md?"
        alert.informativeText = "No document is open."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
