import SwiftUI

struct AddRemoteView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let existing: RemoteSpec?
    @State private var isGit: Bool
    @State private var name: String
    @State private var destination: String
    @State private var remotePath: String
    @State private var gitURL: String

    init(existing: RemoteSpec? = nil, prefill: RemoteSpec? = nil) {
        self.existing = existing
        let seed = existing ?? prefill
        _isGit = State(initialValue: seed?.isGit ?? false)
        _name = State(initialValue: seed?.name ?? "")
        _destination = State(initialValue: seed?.sshDestination ?? "")
        _remotePath = State(initialValue: seed?.remotePath ?? "")
        _gitURL = State(initialValue: seed?.gitURL ?? "")
    }

    private var valid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isGit {
            // Loose on purpose — https, ssh, scp-style and local paths are all
            // clonable, and git gives a better error than a regex would. A
            // leading dash is the one form that must not reach it as an argument.
            let url = gitURL.trimmingCharacters(in: .whitespaces)
            return !url.isEmpty && !url.hasPrefix("-")
        }
        return destination.contains("@") && remotePath.hasPrefix("/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Add Remote Folder" : "Edit Remote Folder").font(.headline)
            Picker("", selection: $isGit) {
                Text("SSH").tag(false)
                Text("Git").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Form {
                TextField("Name", text: $name)
                if isGit {
                    TextField("Repository", text: $gitURL)
                } else {
                    TextField("SSH  (user@host)", text: $destination)
                    TextField("Remote path  (/srv/docs)", text: $remotePath)
                }
            }
            Text(isGit
                 ? "https://…, git@…, ssh://… or a local path. Cloned read-only into a local cache, then pulled on launch. Uses your existing git credentials — never prompts."
                 : "Uses your ~/.ssh config and keys. Read-only; synced to a local cache.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") {
                    let spec = Self.spec(id: existing?.id, name: name, isGit: isGit,
                                         gitURL: gitURL, destination: destination,
                                         remotePath: remotePath)
                    if existing != nil {
                        // Keep the same id so cacheURL (and marks) are preserved.
                        state.updateRemote(spec)
                    } else {
                        state.addRemote(spec)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    /// The fields for the kind that isn't showing are dropped, so switching an
    /// existing remote from SSH to git (or back) doesn't leave the old one behind
    /// — `isGit` is derived from `gitURL` being present.
    ///
    /// Static and taking the fields rather than reading `self`: this is the one
    /// piece of the sheet that breaks silently (a leftover `sshDestination` sends
    /// a git remote down the rsync path), and a view's `@State` can't be tested.
    static func spec(id: String?, name: String, isGit: Bool,
                     gitURL: String, destination: String, remotePath: String) -> RemoteSpec {
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        var spec = RemoteSpec(id: id ?? UUID().uuidString, name: trimmed(name))
        if isGit {
            spec.gitURL = trimmed(gitURL)
        } else {
            spec.sshDestination = trimmed(destination)
            spec.remotePath = trimmed(remotePath)
        }
        return spec
    }
}
