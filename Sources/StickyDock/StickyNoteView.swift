import SwiftUI
import StickyDockCore

/// A note living in its own window on the desktop.
///
/// The chrome only appears on hover, so a note sitting on the desktop is just a
/// coloured rectangle of text, which is the whole point of a sticky note.
struct StickyNoteView: View {
    @EnvironmentObject private var state: AppState
    let noteId: String

    @State private var text = ""
    @State private var showChrome = false
    @State private var confirmingDelete = false
    @FocusState private var focused: Bool

    /// Read through `AppState`, not straight out of `detachedNotes`. During the
    /// drag out of the deck that list has not been refreshed yet, so this note is
    /// not in it, and the view would render with default colour and no text.
    private var note: Note? { state.note(withId: noteId) }
    private var color: NoteColor { note?.color ?? .grey }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.fill(color)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                dragStrip
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .foregroundStyle(Theme.ink)
                    // Without an explicit greedy frame the editor takes its own
                    // narrow intrinsic width and every word wraps onto its own
                    // line, which looks broken at a glance.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .onChange(of: text) { _, new in
                        state.updateText(new, for: noteId)
                    }
                if showChrome { colorStrip }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { text = note?.text ?? "" }
        // The window is built before the lists refresh, so seed the text again
        // once the note becomes visible to SwiftUI's change tracking.
        .onChange(of: note?.id) { _, _ in
            if text.isEmpty { text = note?.text ?? "" }
        }
        // A sync can rewrite this note while the window sits open. Without this
        // the window would keep showing text that is no longer what is stored.
        .onChange(of: note?.text ?? "") { _, incoming in
            if incoming != text { text = incoming }
        }
        .onHover { showChrome = $0 }
        .confirmationDialog(
            "Delete this note for good?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { state.delete(noteId) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will also be removed from Apple Notes on your other devices.")
        }
    }

    /// The one place the window can be dragged from. The text view below takes
    /// its own clicks, so `isMovableByWindowBackground` alone is not enough.
    private var dragStrip: some View {
        HStack(spacing: 6) {
            if showChrome {
                Button { state.returnToDock(noteId) } label: {
                    Image(systemName: "arrow.right.to.line.compact")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Put this note back in the dock")
                .accessibilityLabel("Return to dock")
            }
            Spacer()
            if showChrome {
                Button { confirmingDelete = true } label: {
                    Image(systemName: "trash").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Delete for good")
            }
        }
        .foregroundStyle(Theme.inkSoft)
        .frame(height: 18)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    private var colorStrip: some View {
        HStack(spacing: 7) {
            ForEach(NoteColor.allCases, id: \.self) { color in
                Button { state.setColor(color, for: noteId) } label: {
                    Circle()
                        .fill(Theme.fill(color))
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle().strokeBorder(
                                self.color == color ? Theme.ink : .black.opacity(0.18),
                                lineWidth: self.color == color ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }
}
