import SwiftUI
import StickyDockCore

/// The three states of the dock: a stripe of dots, a fanned deck, one open note.
struct DockContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if !state.isExpanded {
                collapsedStripe
            } else if let note = state.selectedNote {
                NoteEditorView(note: note)
                    .environmentObject(state)
                    .padding(6)
            } else {
                fannedDeck
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Dormant

    /// A 14pt stripe, one dot per note. Deliberately tiny: it has to sit on the
    /// edge of the screen all day without asking for attention.
    private var collapsedStripe: some View {
        VStack(spacing: 5) {
            Spacer(minLength: 6)
            ForEach(state.notes.prefix(14)) { note in
                Capsule()
                    .fill(Theme.fill(note.color))
                    .frame(width: 6, height: 14)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
            }
            if state.notes.count > 14 {
                Text("+")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            if state.notes.isEmpty {
                Circle()
                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement()
        .accessibilityLabel(Text("StickyDock, \(state.notes.count) notes. Move the pointer here to open."))
    }

    // MARK: - Fanned

    private var fannedDeck: some View {
        VStack(spacing: 0) {
            HStack {
                Text("StickyDock").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { state.newNote() } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("New note")
                .accessibilityLabel("New note")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if state.notes.isEmpty {
                emptyState(detachedCount: state.detachedNotes.count)
            } else {
                // A gesture nobody knows about does not exist.
                Text("Drag a note out to put it on the desktop")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(state.notes.enumerated()), id: \.element.id) { index, note in
                            NoteCardView(note: note, isTop: index == 0) {
                                state.selectedNoteId = note.id
                            }
                            .environmentObject(state)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }

            Divider().opacity(0.2)
            HStack(spacing: 4) {
                Image(systemName: state.syncProblem == nil
                      ? "checkmark.icloud" : "exclamationmark.icloud")
                Text(state.syncProblem ?? state.lastSyncSummary).lineLimit(1)
            }
            .font(.system(size: 10))
            .foregroundStyle(state.syncProblem == nil ? Color.secondary : Color.red)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
    }

    private func emptyState(detachedCount: Int) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "note.text").font(.system(size: 26)).foregroundStyle(.tertiary)
            // An empty deck means something different when notes are on the
            // desktop. Saying "no notes yet" there would just be wrong.
            Text(detachedCount == 0
                 ? "No notes yet"
                 : "All \(detachedCount) notes are on the desktop")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New note") { state.newNote() }
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
