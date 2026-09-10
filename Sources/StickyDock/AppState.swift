import Foundation
import SwiftUI
import StickyDockCore

/// Everything the UI reads and every action it can take.
///
/// The views hold no state of their own beyond what the user is typing right
/// now, so there is exactly one answer to "what does the app currently think".
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var isExpanded = false
    @Published var selectedNoteId: String?
    @Published var lastSyncSummary = "Not synced yet"
    @Published var syncProblem: String?

    let store: NoteStoring
    private let onNotesChanged: () -> Void
    /// Fired after an edit settles, so a sync can follow shortly after.
    var onLocalEdit: (() -> Void)?

    private var saveTask: Task<Void, Never>?

    init(store: NoteStoring, onNotesChanged: @escaping () -> Void = {}) {
        self.store = store
        self.onNotesChanged = onNotesChanged
        reload()
    }

    var selectedNote: Note? {
        guard let selectedNoteId else { return nil }
        return notes.first { $0.id == selectedNoteId }
    }

    func reload() {
        notes = (try? store.allActive()) ?? []
        // A note deleted or archived underneath the editor must not leave the
        // editor showing a ghost.
        if let id = selectedNoteId, !notes.contains(where: { $0.id == id }) {
            selectedNoteId = nil
        }
        onNotesChanged()
    }

    // MARK: - Actions

    @discardableResult
    func newNote() -> Note {
        let note = Note(
            color: NoteColor.allCases.randomElement() ?? .yellow,
            sortIndex: (try? store.nextSortIndex()) ?? 0
        )
        try? store.upsert(note)
        reload()
        selectedNoteId = note.id
        isExpanded = true
        return note
    }

    /// Writes are debounced. Every keystroke hitting SQLite would be wasteful,
    /// and every keystroke triggering a sync would hammer Apple Events.
    func updateText(_ text: String, for noteId: String) {
        guard var note = notes.first(where: { $0.id == noteId }) else { return }
        note.text = text
        note.updatedAt = Date()
        if let index = notes.firstIndex(where: { $0.id == noteId }) {
            notes[index] = note
        }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            try? self.store.upsert(note)
            self.reload()
            self.onLocalEdit?()
        }
    }

    /// Called before the app quits, so the last keystrokes are never lost to the
    /// debounce timer.
    func flushPendingEdit() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        for note in notes { try? store.upsert(note) }
    }

    func setColor(_ color: NoteColor, for noteId: String) {
        guard var note = notes.first(where: { $0.id == noteId }) else { return }
        note.color = color
        note.updatedAt = Date()
        try? store.upsert(note)
        reload()
        onLocalEdit?()
    }

    func archive(_ noteId: String) {
        try? store.archive(id: noteId, at: Date())
        if selectedNoteId == noteId { selectedNoteId = nil }
        reload()
        onLocalEdit?()
    }

    func delete(_ noteId: String) {
        try? store.delete(id: noteId)
        if selectedNoteId == noteId { selectedNoteId = nil }
        reload()
        onLocalEdit?()
    }

    func unarchive(_ noteId: String) {
        guard var note = try? store.find(id: noteId) else { return }
        note.archivedAt = nil
        note.updatedAt = Date()
        try? store.upsert(note)
        reload()
        onLocalEdit?()
    }
}
