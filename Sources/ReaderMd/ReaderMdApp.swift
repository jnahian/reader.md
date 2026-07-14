import SwiftUI
import AppKit
import Sparkle

// Auto-update via Sparkle. Only starts in the packaged .app (SUFeedURL in
// Info.plist); nil under `swift run` so dev launches don't error on a missing feed.
private let updaterController: SPUStandardUpdaterController? = {
    guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return nil }
    return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
}()

@main
struct ReaderMdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Reader.md") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 720, minHeight: 460)
                .preferredColorScheme(state.theme.colorScheme)
                .onOpenURL { url in
                    if url.isFileURL {
                        state.open(FileNode(url: url, isDirectory: false))
                        return
                    }
                    switch ReaderURL.action(for: url) {
                    case .open(let path):
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
                // Without this, SwiftUI answers every incoming readermd:// URL by
                // opening a *second* window instead of routing it to the existing one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Reader.md") { showAboutPanel() }
                Button("Check for Updates…") { updaterController?.checkForUpdates(nil) }
                    .disabled(updaterController == nil)
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
                Divider()
                Button("Export as PDF…") { state.triggerExport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(state.selectedFile == nil)
                Button("Reload") { state.triggerReload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(state.selectedFile == nil)
                Divider()
                Button("Install reader Command Line Tool…") { InstallCLI.run() }
            }

            CommandMenu("Find") {
                Button("Find in Page") { state.focusFind.toggle() }
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
                Divider()
                Button("Increase Text") { state.adjustFontScale(0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Text") { state.adjustFontScale(-0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { state.resetFontScale() }
                    .keyboardShortcut("0", modifiers: .command)
                Picker("Column Width", selection: Binding(
                    get: { state.contentWidth },
                    set: { state.setContentWidth($0) }
                )) {
                    ForEach(ContentWidth.allCases, id: \.self) { width in
                        Text(width.displayName).tag(width)
                    }
                }
                Button("Cycle Column Width") { state.cycleContentWidth() }
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
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/jnahian/reader.md/issues/new")!)
                }
                Button("View on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/jnahian/reader.md")!)
                }
            }
        }
    }
}

// ponytail: fallback version for `swift run` (no Info.plist); keep in sync with make-app.sh.
private func showAboutPanel() {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "1.10.0"
    let build = info?["CFBundleVersion"] as? String ?? "dev"
    let credits = NSAttributedString(
        string: "A native macOS markdown viewer.\nMermaid & LaTeX, live reload, PDF export.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
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
                  let self
            else { return event }
            // Deferred, not called inline: the quit path runs a modal alert, and
            // spinning a modal loop from inside sendEvent() swallows it silently.
            DispatchQueue.main.async { self.closeFileOrQuit(nil) }
            return nil
        }
        // The menu item itself is rebuilt constantly, so re-point it each time the user
        // pulls the menu bar down — otherwise clicking Close would still quit.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retargetCloseItem() }
        }
    }

    private func retargetCloseItem() {
        let items = NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items) ?? []
        guard let close = items.first(where: { $0.action == #selector(NSWindow.performClose(_:)) })
        else { return }
        // Target is `self`, not nil: left to the responder chain the item validates as
        // disabled and the menu entry greys out.
        close.target = self
        close.action = #selector(closeFileOrQuit(_:))
    }

    @MainActor @objc func closeFileOrQuit(_ sender: Any?) {
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
