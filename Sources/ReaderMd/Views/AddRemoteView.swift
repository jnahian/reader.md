import SwiftUI

struct AddRemoteView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let existing: RemoteSpec?
    @State private var name: String
    @State private var destination: String
    @State private var remotePath: String

    init(existing: RemoteSpec? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _destination = State(initialValue: existing?.sshDestination ?? "")
        _remotePath = State(initialValue: existing?.remotePath ?? "")
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        destination.contains("@") &&
        remotePath.hasPrefix("/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Add Remote Folder" : "Edit Remote Folder").font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("SSH  (user@host)", text: $destination)
                TextField("Remote path  (/srv/docs)", text: $remotePath)
            }
            Text("Uses your ~/.ssh config and keys. Read-only; synced to a local cache.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add" : "Save") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    let d = destination.trimmingCharacters(in: .whitespaces)
                    let p = remotePath.trimmingCharacters(in: .whitespaces)
                    if let existing {
                        // Keep the same id so cacheURL (and marks) are preserved.
                        state.updateRemote(RemoteSpec(id: existing.id, name: n, sshDestination: d, remotePath: p))
                    } else {
                        state.addRemote(RemoteSpec(name: n, sshDestination: d, remotePath: p))
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
