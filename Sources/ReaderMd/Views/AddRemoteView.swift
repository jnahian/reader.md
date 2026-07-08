import SwiftUI

struct AddRemoteView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var destination = ""
    @State private var remotePath = ""

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        destination.contains("@") &&
        remotePath.hasPrefix("/")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Remote Folder").font(.headline)
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
                Button("Add") {
                    state.addRemote(RemoteSpec(
                        name: name.trimmingCharacters(in: .whitespaces),
                        sshDestination: destination.trimmingCharacters(in: .whitespaces),
                        remotePath: remotePath.trimmingCharacters(in: .whitespaces)))
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
