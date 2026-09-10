import SwiftUI
import StickyDockCore

/// Search across everything, archived notes included.
///
/// Archive is the reason this window exists. Archiving is only safe to reach for
/// if the note is genuinely findable afterwards.
struct AllNotesView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var results: [Note] = []
    let onOpen: (Note) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search titles, bodies and archived notes", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(10)
            Divider()

            if results.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(query.isEmpty ? "No notes yet" : "Nothing matches \"\(query)\"")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(results) { note in
                    row(for: note)
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .onAppear(perform: refresh)
        .onChange(of: query) { _, _ in refresh() }
        .onChange(of: state.notes) { _, _ in refresh() }
    }

    private func row(for note: Note) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.fill(note.color))
                .frame(width: 6, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if note.isArchived {
                        badge("Archived")
                    } else if note.isDetached {
                        badge("On desktop")
                    }
                }
                Text(note.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .opacity(note.isArchived ? 0.65 : 1)

            Spacer()

            if note.isArchived {
                Button("Unarchive") { state.unarchive(note.id) }
                    .controlSize(.small)
            } else {
                Button(note.isDetached ? "Show" : "Open") { onOpen(note) }
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !note.isArchived { onOpen(note) } }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(.secondary.opacity(0.18)))
    }

    private func refresh() {
        results = (try? state.store.search(query)) ?? []
    }
}
