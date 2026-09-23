import AppKit
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
    /// The tab the pointer is over. Drives the sneak peek, and it is the panel's
    /// width that follows it, so it lives here rather than inside a view.
    @Published var hoveredNoteId: String?
    /// The tab being dragged up or down the deck, if any.
    @Published private(set) var reorderingNoteId: String?
    /// How far it has been carried, and the slot it would land in. Nothing is
    /// written until the mouse comes up: a write per pixel would be a sync per
    /// pixel, and the order is what the other Mac reads.
    @Published private(set) var reorderDrag: Double = 0
    @Published private(set) var reorderTarget: Int?
    /// Watches for the mouse coming up. SwiftUI's `onEnded` is reliable here,
    /// but a reorder that never ends leaves the deck frozen in a half-dragged
    /// order, so there is a second way out that does not depend on SwiftUI.
    private var reorderWatchdog: Timer?

    let store: NoteStoring
    /// Fired after an edit settles, so a sync can follow shortly after.
    var onLocalEdit: (() -> Void)?

    private var saveTask: Task<Void, Never>?
    /// The note being typed into, held until the debounce fires or the app
    /// quits. Only this note is ever flushed.
    private var pendingEdit: UnsavedEdit?

    init(store: NoteStoring) {
        self.store = store
        reload()
    }

    var selectedNote: Note? {
        guard let selectedNoteId else { return nil }
        return notes.first { $0.id == selectedNoteId }
    }

    /// Drops the peek at once, for the cases where the deck itself is going away.
    func clearHoverImmediately() {
        hoveredNoteId = nil
    }

    var hoveredNote: Note? {
        guard let hoveredNoteId, hoveredNoteId != selectedNoteId else { return nil }
        // A peek opening mid-drag would widen the panel under the pointer, which
        // is the feedback loop that made the dock oscillate once already.
        guard reorderingNoteId == nil else { return nil }
        return notes.first { $0.id == hoveredNoteId }
    }

    /// Where the carried tab started. Read from the live list, so a sync landing
    /// mid-drag cannot leave it pointing at the wrong row.
    private var reorderOrigin: Int? {
        guard let reorderingNoteId else { return nil }
        return notes.firstIndex { $0.id == reorderingNoteId }
    }

    /// How far this tab should be drawn from where it normally sits.
    func tabOffset(for note: Note, at index: Int) -> Double {
        guard let origin = reorderOrigin, let target = reorderTarget else { return 0 }
        if note.id == reorderingNoteId {
            return NoteOrder.carriedOffset(drag: reorderDrag, origin: origin,
                                           pitch: Theme.tabPitch, count: notes.count)
        }
        return NoteOrder.displacement(atIndex: index, origin: origin, target: target,
                                      pitch: Theme.tabPitch)
    }

    /// Owns the desktop windows. Set by the app delegate once, so the views can
    /// ask for a note to be detached without knowing anything about AppKit.
    weak var windows: StickyWindowManager?

    /// True while a keystroke is waiting to be written.
    var hasPendingEdit: Bool { pendingEdit != nil }

    func reload() {
        notes = (try? store.allDocked()) ?? []
        detachedNotes = (try? store.allDetached()) ?? []
        // The database is behind the keyboard by up to one debounce interval, so
        // publishing it raw would move the note being typed into backwards, the
        // editor would notice the difference and rewrite itself, and the
        // characters typed since the last save would be gone. This is what made
        // typing blink and lose text. Whatever is pending wins.
        if let pendingEdit {
            notes = pendingEdit.applied(to: notes)
            detachedNotes = pendingEdit.applied(to: detachedNotes)
        }
        // A note deleted or archived underneath the editor must not leave the
        // editor showing a ghost.
        if let id = selectedNoteId, !notes.contains(where: { $0.id == id }) {
            selectedNoteId = nil
        }
        if let id = hoveredNoteId, !notes.contains(where: { $0.id == id }) {
            hoveredNoteId = nil
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
        hoveredNoteId = nil
        selectedNoteId = note.id
        isExpanded = true
        return note
    }

    /// Writes are debounced. Every keystroke hitting SQLite would be wasteful,
    /// and every keystroke triggering a sync would hammer Apple Events.
    func updateRich(_ rich: RichText, for noteId: String) {
        // Moving to a different note before the debounce fires must not throw
        // away what was typed into the previous one.
        if let pending = pendingEdit, pending.noteId != noteId {
            saveTask?.cancel()
            saveTask = nil
            commitPendingEdit()
        }
        guard var shown = anyNote(noteId), shown.rich != rich else { return }
        // Show it straight away; the write is debounced behind it.
        shown.rich = rich
        shown.updatedAt = Date()
        replaceInPublishedLists(shown)

        pendingEdit = UnsavedEdit(noteId: noteId, rich: rich)
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
        guard let edit = pendingEdit else { return }
        pendingEdit = nil
        let rich = edit.rich
        mutate(edit.noteId) { note in
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

    // MARK: - Reordering the deck

    func beginReorder(_ noteId: String) {
        guard reorderingNoteId == nil, let origin = notes.firstIndex(where: { $0.id == noteId })
        else { return }
        reorderingNoteId = noteId
        reorderDrag = 0
        reorderTarget = origin
        // It has to see the button go down before it will act on it coming up.
        // Without that it reads "no button pressed" on its first tick, before
        // the press has registered, and cancels the drag that just started.
        var sawButtonDown = false
        // `.common` modes, or it never fires: dragging puts the run loop into
        // event tracking and a default-mode timer sits there silently.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard NSEvent.pressedMouseButtons != 0 else {
                if sawButtonDown { Task { @MainActor in self?.endReorder() } }
                return
            }
            sawButtonDown = true
        }
        RunLoop.main.add(timer, forMode: .common)
        reorderWatchdog = timer
    }

    /// `verticalDrag` is how far the pointer has moved down the screen since the
    /// drag began, in points. Down is positive, matching the deck's own order.
    func updateReorder(_ noteId: String, verticalDrag: Double) {
        guard reorderingNoteId == noteId, let origin = reorderOrigin else { return }
        reorderDrag = verticalDrag
        let target = NoteOrder.targetIndex(
            movingFrom: origin, byVerticalDrag: verticalDrag,
            pitch: Theme.tabPitch, count: notes.count
        )
        guard target != reorderTarget else { return }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            reorderTarget = target
        }
    }

    /// Writes the dragged order down, once.
    func endReorder() {
        reorderWatchdog?.invalidate()
        reorderWatchdog = nil
        let target = reorderTarget
        let noteId = reorderingNoteId
        reorderingNoteId = nil
        reorderTarget = nil
        reorderDrag = 0
        guard let target, let noteId else { return }
        let moved = NoteOrder.reindexed(NoteOrder.moving(noteId, to: target, in: notes))
        guard !moved.isEmpty else { return }
        for note in moved {
            // Through the store, never a published copy: a sync running in the
            // background may have just written a notesId onto this note.
            mutate(note.id) { stored in
                stored.sortIndex = note.sortIndex
                stored.updatedAt = note.updatedAt
            }
        }
        reload()
        // The new order has to reach the other Mac, and that goes out through
        // the sidecar on the next sync.
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
        hoveredNoteId = nil
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
