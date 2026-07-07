import SwiftUI

/// Status-bar badge surfacing highlights whose anchored text is no longer
/// found in the document (edited/deleted out from under them) — orphans are
/// never silently dropped, just flagged here until removed.
struct OrphanedMarksBadge: View {
    @EnvironmentObject var state: AppState
    @State private var showList = false

    var body: some View {
        if !state.orphanedMarkIDs.isEmpty {
            Button {
                showList.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(state.orphanedMarkIDs.count)")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .font(.system(size: 11))
            .popover(isPresented: $showList, arrowEdge: .top) {
                OrphanedMarksList()
            }
        }
    }
}

private struct OrphanedMarksList: View {
    @EnvironmentObject var state: AppState

    private var orphaned: [Mark] {
        state.marks.filter { state.orphanedMarkIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Orphaned highlights")
                .font(.system(size: 12, weight: .semibold))
            Text("This text was no longer found in the file — the highlight below couldn't be re-anchored.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Divider()
            ForEach(orphaned) { mark in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Circle().fill(mark.color.swiftUIColor).frame(width: 8, height: 8)
                        Text(mark.anchor.quote)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        Button {
                            state.deleteMark(mark.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    if let note = mark.comments.first?.text {
                        HStack(spacing: 4) {
                            Image(systemName: "note.text")
                            Text(note)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
