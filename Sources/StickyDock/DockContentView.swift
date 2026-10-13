import SwiftUI
import StickyDockCore

/// The dock: a stripe at rest, a column of tabs when reached for, and one note
/// opened clear of the deck.
struct DockContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if !state.isExpanded {
                collapsedStripe
            } else {
                HStack(alignment: .top, spacing: 8) {
                    leftPane
                    tabColumn
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    // MARK: - At rest

    /// A 14pt stripe, one coloured dash per note. Deliberately tiny: it has to
    /// sit on the edge of the screen all day without asking for attention.
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
                Text("+").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            if state.notes.isEmpty {
                Circle()
                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
            Spacer(minLength: 6)
        }
        // The window is a constant height now, so the pill sizes itself to the
        // notes and sits in the middle of it rather than filling the whole edge.
        .frame(maxWidth: .infinity)
        .frame(height: stripeHeight)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.ultraThinMaterial)
        )
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel(Text(
            "StickyDock, \(state.notes.count) notes. Move the pointer here to open."
        ))
    }

    private var stripeHeight: CGFloat { Theme.stripeHeight(noteCount: state.notes.count) }

    private var deck: DeckGeometry { Theme.deck(noteCount: state.notes.count) }

    // MARK: - Reached for

    /// The notes shingle down the edge, each keeping its colour and its own
    /// vertical tab.
    private var tabColumn: some View {
        // Negative spacing is what shingles the tabs. It comes from the deck
        // geometry, so a crowded deck overlaps more instead of running off the
        // bottom of the panel.
        VStack(spacing: deck.pitch - Theme.tabHeight) {
            if state.notes.isEmpty {
                emptyTab
            } else {
                ForEach(Array(state.notes.enumerated()), id: \.element.id) { index, note in
                    NoteTabView(
                        note: note,
                        index: index,
                        isSelected: state.selectedNoteId == note.id
                    ) {
                        state.selectedNoteId = note.id
                    }
                    .environmentObject(state)
                    .offset(y: state.tabOffset(for: note, at: index))
                    .zIndex(zIndex(for: note, at: index))
                }
            }
            Spacer(minLength: 8)
            newNoteButton
        }
        .frame(width: Theme.tabWidth)
        .padding(.vertical, 10)
    }

    /// The tab being carried goes above everything, so it is never drawn behind
    /// the neighbour it is passing.
    private func zIndex(for note: Note, at index: Int) -> Double {
        if state.reorderingNoteId == note.id { return 200 }
        return state.selectedNoteId == note.id ? 100 : Double(-index)
    }

    private var emptyTab: some View {
        VStack(spacing: 4) {
            Image(systemName: "note.text").font(.system(size: 15)).foregroundStyle(.secondary)
            Text(state.detachedNotes.isEmpty ? "Empty" : "On desk")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: Theme.tabWidth, height: 56)
        .background(TabShape().fill(.ultraThinMaterial))
    }

    private var newNoteButton: some View {
        HStack(spacing: 5) {
            Button { state.newNote() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary, .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help("New note  (⌃⌥N)")
            .accessibilityLabel("New note")

            Image(systemName: state.syncProblem == nil ? "checkmark.icloud" : "exclamationmark.icloud")
                .font(.system(size: 11))
                .foregroundStyle(state.syncProblem == nil ? Color.secondary : Color.red)
                .help(state.syncProblem ?? state.lastSyncSummary)
        }
        .padding(.trailing, 6)
        .frame(width: Theme.tabWidth, alignment: .trailing)
    }

    // MARK: - Opened clear of the deck

    /// Lines the peek up with its tab, then pulls it back inside the panel if
    /// that would push it off the bottom.
    private func peekOffset(for note: Note) -> CGFloat {
        guard let index = state.notes.firstIndex(where: { $0.id == note.id }) else { return 0 }
        let raw = CGFloat(index) * deck.pitch
        let maximum = max(0, deck.panelHeight - 200)
        return min(raw, maximum)
    }

    @ViewBuilder
    private var leftPane: some View {
        if let note = state.selectedNote {
            NoteEditorView(note: note)
                .environmentObject(state)
                // A new identity per note. Without it SwiftUI reuses the editor
                // and its @State, so switching notes left the previous note's
                // text on screen under the new note's title.
                .id(note.id)
                .frame(width: Theme.editorWidth)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let hovered = state.hoveredNote {
            // Sits beside the tab the pointer is actually on, not at the top of
            // the panel, so the peek reads as belonging to that note.
            VStack(spacing: 0) {
                Spacer().frame(height: peekOffset(for: hovered))
                NotePeekView(note: hovered)
                Spacer(minLength: 0)
            }
            .frame(width: Theme.peekWidth)
            .transition(.opacity)
            .allowsHitTesting(false)
        } else {
            Color.clear.frame(width: 0)
        }
    }
}
