import Foundation
import Testing
@testable import StickyDockCore

@Suite("NoteStore")
struct NoteStoreTests {

    /// Each test gets its own database file, so nothing leaks between them.
    private func withStore<T>(_ body: (NoteStore) throws -> T) throws -> T {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NoteStore(path: dir.appendingPathComponent("notes.sqlite").path)
        return try body(store)
    }

    @Test func upsertThenFindReturnsSameNote() throws {
        try withStore { store in
            let note = Note(text: "hello")
            try store.upsert(note)
            let found = try store.find(id: note.id)
            #expect(found?.text == "hello")
            #expect(found?.color == .yellow)
        }
    }

    @Test func upsertTwiceUpdatesRatherThanDuplicates() throws {
        try withStore { store in
            var note = Note(text: "first")
            try store.upsert(note)
            note.text = "second"
            try store.upsert(note)
            #expect(try store.all().count == 1)
            #expect(try store.find(id: note.id)?.text == "second")
        }
    }

    @Test func allActiveExcludesArchivedButAllIncludesIt() throws {
        try withStore { store in
            let live = Note(text: "live")
            let dead = Note(text: "dead", archivedAt: Date())
            try store.upsert(live)
            try store.upsert(dead)
            #expect(try store.allActive().map(\.text) == ["live"])
            #expect(try store.all().count == 2)
        }
    }

    @Test func findByNotesIdWorks() throws {
        try withStore { store in
            let note = Note(notesId: "x-coredata://abc/ICNote/p1", text: "a")
            try store.upsert(note)
            #expect(try store.find(notesId: "x-coredata://abc/ICNote/p1")?.id == note.id)
        }
    }

    @Test func findByNotesIdReturnsNilForUnknownId() throws {
        try withStore { store in
            try store.upsert(Note(text: "a"))
            #expect(try store.find(notesId: "nope") == nil)
        }
    }

    @Test func searchMatchesBodyCaseInsensitively() throws {
        try withStore { store in
            try store.upsert(Note(text: "Buy MILK tomorrow"))
            try store.upsert(Note(text: "call the bank"))
            #expect(try store.search("milk").count == 1)
            #expect(try store.search("MILK").count == 1)
        }
    }

    @Test func searchMatchesArchivedNotesToo() throws {
        try withStore { store in
            try store.upsert(Note(text: "old receipt", archivedAt: Date()))
            #expect(try store.search("receipt").count == 1)
        }
    }

    @Test func searchWithWildcardCharactersIsTakenLiterally() throws {
        // A raw LIKE would treat % as "match anything" and return everything.
        try withStore { store in
            try store.upsert(Note(text: "plain note"))
            try store.upsert(Note(text: "100% done"))
            #expect(try store.search("%").count == 1)
        }
    }

    @Test func archiveSetsTheTimestamp() throws {
        try withStore { store in
            let note = Note(text: "a")
            try store.upsert(note)
            let when = Date()
            try store.archive(id: note.id, at: when)
            #expect(try store.find(id: note.id)?.isArchived == true)
            #expect(try store.allActive().isEmpty)
        }
    }

    @Test func deleteRemovesTheRow() throws {
        try withStore { store in
            let note = Note(text: "a")
            try store.upsert(note)
            try store.delete(id: note.id)
            #expect(try store.find(id: note.id) == nil)
        }
    }

    @Test func allActiveIsOrderedBySortIndexThenNewestFirst() throws {
        try withStore { store in
            let old = Date(timeIntervalSince1970: 1000)
            let new = Date(timeIntervalSince1970: 2000)
            try store.upsert(Note(text: "b", updatedAt: old, sortIndex: 1))
            try store.upsert(Note(text: "c", updatedAt: new, sortIndex: 2))
            try store.upsert(Note(text: "a", updatedAt: new, sortIndex: 1))
            #expect(try store.allActive().map(\.text) == ["a", "b", "c"])
        }
    }

    @Test func storeSurvivesReopeningTheSameFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("notes.sqlite").path

        let id: String
        do {
            let store = try NoteStore(path: path)
            let note = Note(text: "persisted")
            id = note.id
            try store.upsert(note)
        }
        let reopened = try NoteStore(path: path)
        #expect(try reopened.find(id: id)?.text == "persisted")
    }

    @Test func detachedNotesLeaveTheDeckButStayActive() throws {
        try withStore { store in
            try store.upsert(Note(id: "docked", text: "in the dock"))
            try store.upsert(Note(
                id: "floating", text: "on the desktop", isDetached: true,
                frame: NoteFrame(x: 10, y: 20, width: 260, height: 220)
            ))
            #expect(try store.allDocked().map(\.id) == ["docked"])
            #expect(try store.allDetached().map(\.id) == ["floating"])
            #expect(try store.allActive().count == 2, "both are still active notes")
        }
    }

    @Test func anArchivedDetachedNoteIsInNeitherList() throws {
        try withStore { store in
            try store.upsert(Note(id: "a", text: "x", archivedAt: Date(), isDetached: true))
            #expect(try store.allDocked().isEmpty)
            #expect(try store.allDetached().isEmpty)
        }
    }

    @Test func theWindowFrameSurvivesARestart() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("notes.sqlite").path

        let frame = NoteFrame(x: 120.5, y: 340.25, width: 300, height: 260)
        do {
            let store = try NoteStore(path: path)
            try store.upsert(Note(id: "f", text: "x", isDetached: true, frame: frame))
        }
        let reopened = try NoteStore(path: path)
        #expect(try reopened.find(id: "f")?.frame == frame)
        #expect(try reopened.find(id: "f")?.isDetached == true)
    }

    @Test func aNoteWithNoFrameReportsNilRatherThanZeros() throws {
        try withStore { store in
            try store.upsert(Note(id: "n", text: "x"))
            #expect(try store.find(id: "n")?.frame == nil)
        }
    }

    @Test func aDatabaseWrittenBeforeDetachedWindowsExistedStillOpens() throws {
        // The v1 to v2 migration has to work on a real v1 file, not just a fresh
        // one, or an existing install loses every note on upgrade.
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("notes.sqlite").path

        try NoteStore.makeVersionOneDatabaseForTesting(path: path, noteId: "old", text: "kept")
        let migrated = try NoteStore(path: path)
        #expect(try migrated.find(id: "old")?.text == "kept")
        #expect(try migrated.find(id: "old")?.isDetached == false)
    }

    @Test func aTombstonedNoteIsHiddenFromEveryUserFacingList() throws {
        try withStore { store in
            try store.upsert(Note(id: "live", text: "still here"))
            try store.upsert(Note(id: "gone", text: "deleted", deletedAt: Date()))
            #expect(try store.allDocked().map(\.id) == ["live"])
            #expect(try store.allActive().map(\.id) == ["live"])
            #expect(try store.search("deleted").isEmpty)
            #expect(try store.search("").map(\.id) == ["live"])
            // The sync still needs to see it, or it can never take it out of
            // Apple Notes.
            #expect(try store.all().count == 2)
        }
    }

    @Test func aTombstonedDetachedNoteIsNotRestoredToTheDesktop() throws {
        try withStore { store in
            try store.upsert(Note(id: "gone", text: "x", deletedAt: Date(), isDetached: true))
            #expect(try store.allDetached().isEmpty)
        }
    }

    @Test func markDeletedSetsTheTombstoneWithoutRemovingTheRow() throws {
        try withStore { store in
            try store.upsert(Note(id: "n", text: "x"))
            try store.markDeleted(id: "n", at: Date())
            #expect(try store.find(id: "n")?.isDeleted == true)
        }
    }

    @Test func nextSortIndexIsOneAboveTheHighest() throws {
        try withStore { store in
            #expect(try store.nextSortIndex() == 0)
            try store.upsert(Note(text: "a", sortIndex: 4))
            #expect(try store.nextSortIndex() == 5)
        }
    }
}
