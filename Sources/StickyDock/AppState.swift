import Foundation
import SwiftUI
import StickyDockCore

/// Everything the UI reads and every action it can take.
///
/// The views hold no state of their own beyond what the user is typing right
/// now, so there is exactly one answer to "what does the app currently think".
@MainActor
final class AppState: ObservableObject {
    /// Notes still in the dock. A detached note is deliberately absent here: it
    /// is already visible on the desktop, and showing it twice is confusing.
    @Published private(set) var notes: [Note] = []
    @Published private(set) var detachedNotes: [Note] = []
    @Published var isExpanded = false
    @Published var selectedNoteId: String?
    @Published var lastSyncSummary = "Not synced yet"
    @Published var syncProblem: String?
    /// The note currently being pulled out of the deck. Its card stays in the
    /// list, dimmed, until the drag finishes.
    @Published var draggingNoteId: String?

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

    /// Owns the desktop windows. Set by the app delegate once, so the views can
    /// ask for a note to be detached without knowing anything about AppKit.
    weak var windows: StickyWindowManager?

    func reload() {
        notes = (try? store.allDocked()) ?? []
        detachedNotes = (try? store.allDetached()) ?? []
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
    func updateRich(_ rich: RichText, for noteId: String) {
        guard var note = anyNote(noteId) else { return }
        guard note.rich != rich else { return }
        // The plain text may be identical while only the formatting moved. Sync
        // decides on the hash of the plain text, so that case has to be flagged
        // or it would never be sent.
        if note.text == rich.text { note.styleDirty = true }
        note.rich = rich
        note.updatedAt = Date()
        replaceInPublishedLists(note)
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
        for note in notes + detachedNotes { try? store.upsert(note) }
    }

    func setColor(_ color: NoteColor, for noteId: String) {
        guard var note = anyNote(noteId) else { return }
        note.color = color
        note.updatedAt = Date()
        try? store.upsert(note)
        reload()
        onLocalEdit?()
    }

    func archive(_ noteId: String) {
        windows?.close(noteId: noteId)
        try? store.archive(id: noteId, at: Date())
        if selectedNoteId == noteId { selectedNoteId = nil }
        reload()
        onLocalEdit?()
    }

    func delete(_ noteId: String) {
        windows?.close(noteId: noteId)
        try? store.delete(id: noteId)
        if selectedNoteId == noteId { selectedNoteId = nil }
        reload()
        onLocalEdit?()
    }

    // MARK: - Desktop windows

    /// Lifts a note out of the dock into its own window on the desktop.
    ///
    /// Deliberately does **not** reload the published lists. Reloading here would
    /// remove the card from the deck, SwiftUI would tear down the very view whose
    /// drag gesture is still running, and the drag would die halfway out. The
    /// lists are refreshed by `endDetach` once the mouse comes up.
    /// Pulls a note out of the deck and hands it to the drag.
    ///
    /// Returns immediately; the drag finishes on its own. The published lists
    /// are refreshed only when the mouse comes up, never at the start: reloading
    /// first would remove the card from the deck and tear down the very view
    /// whose gesture began all this.
    func detachByDragging(_ noteId: String, from point: NotePoint) {
        guard var note = try? store.find(id: noteId), !note.isDetached else { return }
        note.isDetached = true
        // Reuse the last known frame so a note dragged out again comes back the
        // size the user left it.
        note.frame = note.frame ?? DetachedFrame.defaultFrame(around: point)
        try? store.upsert(note)
        if selectedNoteId == noteId { selectedNoteId = nil }
        draggingNoteId = noteId

        windows?.beginDrag(noteId: noteId) { [weak self] in
            self?.draggingNoteId = nil
            self?.reload()
        }
    }

    /// Puts a desktop note back into the dock. The window closes; the saved
    /// frame is kept, so dragging it out again returns it to the same spot.
    func returnToDock(_ noteId: String) {
        guard var note = anyNote(noteId) else { return }
        note.isDetached = false
        try? store.upsert(note)
        windows?.close(noteId: noteId)
        reload()
    }

    /// Reads through the store, never a published copy.
    ///
    /// The published lists are deliberately stale during a drag, and writing a
    /// stale copy back would undo the `isDetached` flag that was just set.
    func setFrame(_ frame: NoteFrame, for noteId: String) {
        guard var note = try? store.find(id: noteId), note.frame != frame else { return }
        note.frame = frame
        try? store.upsert(note)
        // Deliberately no reload(): a window move must not republish the whole
        // list and rebuild every view while the user is still dragging.
        replaceInPublishedLists(note)
    }

    // MARK: - Helpers

    /// Finds a note wherever it currently is.
    ///
    /// The published lists are deliberately stale for the length of a drag, so a
    /// view that reads only from them sees nothing and falls back to defaults.
    /// That is what made a note flash yellow and blank on its way out of the
    /// deck. Falling through to the store makes the answer right at every moment
    /// of the drag, and the published lists still drive redraws afterwards.
    func note(withId id: String) -> Note? { anyNote(id) }

    private func anyNote(_ id: String) -> Note? {
        notes.first { $0.id == id }
            ?? detachedNotes.first { $0.id == id }
            ?? (try? store.find(id: id))
    }

    private func replaceInPublishedLists(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        if let index = detachedNotes.firstIndex(where: { $0.id == note.id }) {
            detachedNotes[index] = note
        }
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
