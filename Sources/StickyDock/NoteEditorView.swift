import SwiftUI
import StickyDockCore

struct NoteEditorView: View {
    @EnvironmentObject private var state: AppState
    let note: Note

    @State private var text: String = ""
    @State private var confirmingDelete = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(8)
                .foregroundStyle(Theme.ink)
                .onChange(of: text) { _, new in
                    state.updateText(new, for: note.id)
                }

            Divider().opacity(0.25)
            footer
        }
        .background(Theme.fill(note.color))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onAppear {
            text = note.text
            editorFocused = true
        }
        // Switching notes without closing the editor must load the new text.
        .onChange(of: note.id) { _, _ in text = note.text }
        // A sync can rewrite this note while the editor sits open. Without this
        // the editor keeps showing text that is no longer what is stored, and
        // the next keystroke pushes the stale version back out.
        .onChange(of: note.text) { _, incoming in
            if incoming != text { text = incoming }
        }
        .confirmationDialog(
            "Delete this note for good?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { state.delete(note.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will also be removed from Apple Notes on your other devices. "
               + "Archive keeps it instead.")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                state.selectedNoteId = nil
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to all notes")

            Text(note.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            ForEach(NoteColor.allCases, id: \.self) { color in
                Button {
                    state.setColor(color, for: note.id)
                } label: {
                    Circle()
                        .fill(Theme.fill(color))
                        .frame(width: 15, height: 15)
                        .overlay(
                            Circle().strokeBorder(
                                note.color == color ? Theme.ink : .black.opacity(0.15),
                                lineWidth: note.color == color ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
                .accessibilityLabel(Text("\(color.rawValue) note colour"))
            }

            Spacer()

            Button { state.archive(note.id) } label: {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.plain)
            .help("Archive. Keeps the text, removes it from Apple Notes.")

            Button { confirmingDelete = true } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Delete for good")
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
