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
    /// The tab the pointer is resting on. Drives the sneak peek, and it is the
    /// panel's width that follows it, so it lives here rather than inside a view.
    ///
    /// Set through `hover(_:)`, never directly: it needs the delay.
    @Published private(set) var hoveredNoteId: String?

    let store: NoteStoring
    /// Fired after an edit settles, so a sync can follow shortly after.
    var onLocalEdit: (() -> Void)?

    private var saveTask: Task<Void, Never>?
    private var hoverWork: DispatchWorkItem?
    /// The note being typed into, held until the debounce fires or the app
    /// quits. Only this note is ever flushed.
    private var pendingEdit: (id: String, rich: RichText)?

    init(store: NoteStoring) {
        self.store = store
        reload()
    }

    var selectedNote: Note? {
        guard let selectedNoteId else { return nil }
        return notes.first { $0.id == selectedNoteId }
    }

    /// Hover intent, with a pause before the peek appears and a shorter one
    /// before it goes away.
    ///
    /// Reaching for the screen edge lands the pointer directly on a tab, so
    /// without the pause the deck fanned open and a peek slid out in the same
    /// instant: two width changes on top of each other, which is what made
    /// opening the dock feel clumsy. Now reaching over fans the deck, and
    /// resting on a tab is a separate, deliberate second movement.
    ///
    /// The shorter pause on the way out is what lets the pointer travel from one
    /// tab to the next without the peek blinking shut in between.
    func hover(_ noteId: String?, isEntering: Bool) {
        hoverWork?.cancel()
        guard isExpanded || noteId == nil else { return }

        let delay = isEntering ? 0.30 : 0.12
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isExpanded || noteId == nil else { return }
            // No withAnimation here. The view animates this value itself, and
            // animating it in both places left the peek stuck part way through
            // its fade, showing the desktop through it.
            self.hoveredNoteId = noteId
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Drops the peek at once, with no animation, for the cases where the deck
    /// itself is going away.
    func clearHover() {
        hoverWork?.cancel()
        hoverWork = nil
        hoveredNoteId = nil
    }

    var hoveredNote: Note? {
        guard let hoveredNoteId, hoveredNoteId != selectedNoteId else { return nil }
        return notes.first { $0.id == hoveredNoteId }
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
        if let id = hoveredNoteId, !notes.contains(where: { $0.id == id }) {
            clearHover()
        }
    }

    /// Applies a change to the note **as it is in the store**, never to a
    /// published copy.
    ///
    /// This exists because the published lists can be behind the database: they
    /// are deliberately stale during a drag, and a sync running in the
    /// background writes `notesId` and `syncedHash` without going through them.
    /// Writing a stale copy back would erase a `notesId` that had just been
    /// assigned, and a note with no `notesId` gets created in Apple Notes all
    /// over again. Duplicated notes on the user's phone is the worst outcome
    /// this app has, so every mutation goes through here.
    @discardableResult
    private func mutate(_ noteId: String, _ change: (inout Note) -> Void) -> Note? {
        guard var note = try? store.find(id: noteId) else { return nil }
        change(&note)
        try? store.upsert(note)
        replaceInPublishedLists(note)
        return note
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
        clearHover()
        selectedNoteId = note.id
        isExpanded = true
        return note
    }

    /// Writes are debounced. Every keystroke hitting SQLite would be wasteful,
    /// and every keystroke triggering a sync would hammer Apple Events.
    func updateRich(_ rich: RichText, for noteId: String) {
        // Moving to a different note before the debounce fires must not throw
        // away what was typed into the previous one.
        if let pending = pendingEdit, pending.id != noteId {
            saveTask?.cancel()
            saveTask = nil
            commitPendingEdit()
        }
        guard var shown = anyNote(noteId), shown.rich != rich else { return }
        // Show it straight away; the write is debounced behind it.
        shown.rich = rich
        shown.updatedAt = Date()
        replaceInPublishedLists(shown)

        pendingEdit = (noteId, rich)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            self.commitPendingEdit()
            self.reload()
            self.onLocalEdit?()
        }
    }

    /// Called before the app quits, so the last keystrokes are never lost to the
    /// debounce timer.
    func flushPendingEdit() {
        saveTask?.cancel()
        saveTask = nil
        commitPendingEdit()
    }

    /// Writes only the text and formatting, onto whatever the store holds now.
    ///
    /// Deliberately narrow. An earlier version wrote the whole record, and every
    /// other field on it, back from a published copy, which could erase a
    /// `notesId` a background sync had just assigned.
    private func commitPendingEdit() {
        guard let (noteId, rich) = pendingEdit else { return }
        pendingEdit = nil
        mutate(noteId) { note in
            guard note.rich != rich else { return }
            // Identical text with different formatting is invisible to the sync
            // hash, so that case has to be flagged or it would never be sent.
            if note.text == rich.text { note.styleDirty = true }
            note.rich = rich
            note.updatedAt = Date()
        }
    }

    func setColor(_ color: NoteColor, for noteId: String) {
        mutate(noteId) { note in
            note.color = color
            note.updatedAt = Date()
        }
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

    /// A real delete. The row survives as a tombstone until the next sync has
    /// taken the note out of Apple Notes, otherwise the sync would find it there
    /// and bring it straight back.
    func delete(_ noteId: String) {
        windows?.close(noteId: noteId)
        try? store.markDeleted(id: noteId, at: Date())
        if selectedNoteId == noteId { selectedNoteId = nil }
        reload()
        onLocalEdit?()
    }

    // MARK: - Desktop windows

    /// Pulls a note out of the deck and hands it to the drag.
    ///
    /// Returns immediately; the drag finishes on its own. The published lists
    /// are refreshed only when the mouse comes up, never at the start: reloading
    /// first would remove the card from the deck and tear down the very view
    /// whose gesture began all this.
    func detachByDragging(_ noteId: String, from point: NotePoint) {
        guard let existing = try? store.find(id: noteId), !existing.isDetached else { return }
        mutate(noteId) { note in
            note.isDetached = true
            // Reuse the last known frame so a note dragged out again comes back
            // the size the user left it.
            note.frame = note.frame ?? DetachedFrame.defaultFrame(around: point)
        }
        if selectedNoteId == noteId { selectedNoteId = nil }
        clearHover()
        draggingNoteId = noteId

        windows?.beginDrag(noteId: noteId) { [weak self] in
            self?.draggingNoteId = nil
            self?.reload()
        }
    }

    /// Puts a desktop note back into the dock. The window closes; the saved
    /// frame is kept, so dragging it out again returns it to the same spot.
    func returnToDock(_ noteId: String) {
        mutate(noteId) { $0.isDetached = false }
        windows?.close(noteId: noteId)
        reload()
    }

    /// Reads through the store, never a published copy.
    ///
    /// The published lists are deliberately stale during a drag, and writing a
    /// stale copy back would undo the `isDetached` flag that was just set.
    func setFrame(_ frame: NoteFrame, for noteId: String) {
        guard (try? store.find(id: noteId))?.frame != frame else { return }
        // Deliberately no reload(): a window move must not republish the whole
        // list and rebuild every view while the user is still dragging.
        mutate(noteId) { $0.frame = frame }
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
        mutate(noteId) { note in
            note.archivedAt = nil
            note.updatedAt = Date()
        }
        reload()
        onLocalEdit?()
    }
}
