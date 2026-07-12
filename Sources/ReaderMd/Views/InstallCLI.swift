import AppKit

/// Puts `reader` on the user's PATH. Homebrew users get this for free (the cask's
/// `binary` stanza); this is for people who installed from the DMG.
enum InstallCLI {
    private static let target = "/usr/local/bin/reader"

    static func run() {
        // `URL.path` is already percent-decoded — do not decode it again, or a path
        // containing a literal `%` would be mangled.
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/reader").path
        let fm = FileManager.default

        if fm.fileExists(atPath: target) {
            alert(
                "`reader` is already installed",
                "\(target) already exists. Remove it first if you want to replace it."
            )
            return
        }

        do {
            try fm.createSymbolicLink(atPath: target, withDestinationPath: source)
            alert("Installed", "`reader` is on your PATH. Try `reader --help` in a terminal.")
        } catch {
            // The normal outcome: /usr/local/bin is root-owned. Don't escalate —
            // hand over the command instead.
            let command = "sudo ln -s \"\(source)\" \(target)"
            alertWithCopy(
                "Needs administrator access",
                "/usr/local/bin isn't writable by your user. Run this in a terminal:\n\n\(command)",
                copy: command
            )
        }
    }

    private static func alert(_ title: String, _ message: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        panel.runModal()
    }

    private static func alertWithCopy(_ title: String, _ message: String, copy command: String) {
        let panel = NSAlert()
        panel.messageText = title
        panel.informativeText = message
        panel.addButton(withTitle: "Copy Command")
        panel.addButton(withTitle: "Cancel")
        if panel.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }
}
