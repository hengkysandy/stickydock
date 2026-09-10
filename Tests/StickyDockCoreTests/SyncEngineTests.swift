import Foundation
import Testing
@testable import StickyDockCore

/// One test per row of the decision table in the design document.
///
/// `SyncEngine.plan` is deliberately static and pure, which is what makes this
/// possible: no database, no Notes.app, no clock.
@Suite("SyncEngine.plan")
struct SyncEnginePlanTests {

    private func local(
        _ text: String,
        notesId: String? = nil,
        synced: String? = nil,
        archived: Bool = false,
        id: String = "local-1"
    ) -> Note {
        Note(id: id, notesId: notesId, text: text,
             archivedAt: archived ? Date() : nil, syncedHash: synced)
    }

    private func remote(_ text: String, id: String = "remote-1") -> RemoteNote {
        RemoteNote(id: id, title: NoteHTML.title(of: text), text: text,
                   body: NoteHTML.toHTML(text), modifiedAt: Date())
    }

    // MARK: - The table

    @Test func unchangedOnBothSidesDoesNothing() {
        let hash = ContentHash.of("same")
        let actions = SyncEngine.plan(
            local: [local("same", notesId: "remote-1", synced: hash)],
            remote: [remote("same")]
        )
        #expect(actions == [.none(noteId: "local-1")])
    }

    @Test func localChangedOnlyPushes() {
        let actions = SyncEngine.plan(
            local: [local("edited here", notesId: "remote-1", synced: ContentHash.of("original"))],
            remote: [remote("original")]
        )
        #expect(actions == [.push(noteId: "local-1")])
    }

    @Test func remoteChangedOnlyPulls() {
        let actions = SyncEngine.plan(
            local: [local("original", notesId: "remote-1", synced: ContentHash.of("original"))],
            remote: [remote("edited on the phone")]
        )
        #expect(actions == [.pull(noteId: "local-1", notesId: "remote-1")])
    }

    @Test func bothChangedIsAConflict() {
        let actions = SyncEngine.plan(
            local: [local("mac version", notesId: "remote-1", synced: ContentHash.of("original"))],
            remote: [remote("phone version")]
        )
        #expect(actions == [.conflict(noteId: "local-1", remoteText: "phone version")])
    }

    @Test func bothChangedToTheSameTextIsNotAConflict() {
        // Typing the same correction in both places must not spawn a copy.
        let actions = SyncEngine.plan(
            local: [local("agreed", notesId: "remote-1", synced: ContentHash.of("old"))],
            remote: [remote("agreed")]
        )
        #expect(actions == [.markSynced(noteId: "local-1", hash: ContentHash.of("agreed"))])
    }

    @Test func localNoteWithoutNotesIdIsCreated() {
        let actions = SyncEngine.plan(local: [local("brand new")], remote: [])
        #expect(actions == [.create(noteId: "local-1")])
    }

    @Test func emptyLocalNoteIsNotPushedToNotes() {
        // An empty sticky note is a scratch pad the user has not written in yet.
        // Creating it in Notes would litter the phone with blank notes.
        #expect(SyncEngine.plan(local: [local("   \n  ")], remote: []).isEmpty)
    }

    @Test func unknownRemoteNoteIsAdopted() {
        let actions = SyncEngine.plan(local: [], remote: [remote("made on the phone")])
        #expect(actions == [.adopt(notesId: "remote-1")])
    }

    @Test func noteMissingFromRemoteIsArchivedNeverDeleted() {
        let actions = SyncEngine.plan(
            local: [local("was synced", notesId: "remote-1", synced: ContentHash.of("was synced"))],
            remote: []
        )
        #expect(actions == [.archiveLocal(noteId: "local-1")])
    }

    @Test func archivingLocallyDeletesItFromTheNotesFolder() {
        let hash = ContentHash.of("done with this")
        let actions = SyncEngine.plan(
            local: [local("done with this", notesId: "remote-1", synced: hash, archived: true)],
            remote: [remote("done with this")]
        )
        #expect(actions == [.deleteRemote(noteId: "local-1", notesId: "remote-1")])
    }

    @Test func archivedLocallyButEditedRemotelyIsRestoredNotDeleted() {
        // Someone edited it on the phone after it was archived here. Deleting it
        // would throw away work that was just done. Bring it back instead.
        let actions = SyncEngine.plan(
            local: [local("old text", notesId: "remote-1",
                          synced: ContentHash.of("old text"), archived: true)],
            remote: [remote("just edited on the phone")]
        )
        #expect(actions == [.restore(noteId: "local-1", notesId: "remote-1")])
    }

    @Test func archivedNoteAlreadyGoneFromRemoteNeedsNothing() {
        let actions = SyncEngine.plan(
            local: [local("gone", notesId: "remote-1",
                          synced: ContentHash.of("gone"), archived: true)],
            remote: []
        )
        #expect(actions.isEmpty)
    }

    @Test func archivedNoteThatNeverReachedNotesNeedsNothing() {
        #expect(SyncEngine.plan(local: [local("never pushed", archived: true)], remote: []).isEmpty)
    }

    @Test func emptyOnBothSidesProducesNoActions() {
        #expect(SyncEngine.plan(local: [], remote: []).isEmpty)
    }

    @Test func neverSyncedNoteWithMatchingRemoteTextJustMarksSynced() {
        // Recovering after the local database was deleted and rebuilt.
        let actions = SyncEngine.plan(
            local: [local("identical", notesId: "remote-1", synced: nil)],
            remote: [remote("identical")]
        )
        #expect(actions == [.markSynced(noteId: "local-1", hash: ContentHash.of("identical"))])
    }

    @Test func planIsDeterministicForTheSameInput() {
        let localNotes = [
            local("a", notesId: "remote-1", synced: ContentHash.of("a"), id: "l1"),
            local("b", id: "l2"),
        ]
        let remoteNotes = [remote("a"), remote("orphan", id: "remote-9")]
        #expect(SyncEngine.plan(local: localNotes, remote: remoteNotes)
                == SyncEngine.plan(local: localNotes, remote: remoteNotes))
    }
}

@Suite("SyncEngine.runOnce", .serialized)
struct SyncEngineRunTests {

    private func makeEngine(
        notes: [Note] = [], remote: [RemoteNote] = []
    ) throws -> (SyncEngine, NoteStore, FakeNotesBridge, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try NoteStore(path: dir.appendingPathComponent("n.sqlite").path)
        for note in notes { try store.upsert(note) }
        let bridge = FakeNotesBridge(notes: remote)
        let engine = SyncEngine(store: store, bridge: bridge, sidecar: FakeSidecarStore(),
                                account: "iCloud", folder: "StickyDock")
        return (engine, store, bridge, dir)
    }

    @Test func creatingLocallyPutsTheNoteInNotesAndRecordsTheId() throws {
        let (engine, store, bridge, dir) = try makeEngine(notes: [Note(text: "hello phone")])
        defer { try? FileManager.default.removeItem(at: dir) }

        let report = try engine.runOnce()
        #expect(report.created == 1)
        #expect(bridge.current.map(\.text) == ["hello phone"])

        let saved = try store.all().first
        #expect(saved?.notesId != nil)
        #expect(saved?.syncedHash == ContentHash.of("hello phone"))
    }

    @Test func aSecondSyncAfterAPushDoesNothingAtAll() throws {
        // The loop-breaking guarantee. A push bumps the remote modification date,
        // so anything comparing timestamps would push again for ever.
        let (engine, _, bridge, dir) = try makeEngine(notes: [Note(text: "stable")])
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try engine.runOnce()
        let second = try engine.runOnce()
        #expect(second == SyncReport())
        #expect(bridge.calls.filter { if case .create = $0 { return true }; return false }.count == 1)
    }

    @Test func adoptingARemoteNoteCreatesItLocallyWithItsText() throws {
        let (engine, store, _, dir) = try makeEngine(
            remote: [RemoteNote(id: "r1", title: "From phone", text: "From phone\nbody",
                                modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().adopted == 1)
        let saved = try store.all().first
        #expect(saved?.text == "From phone\nbody")
        #expect(saved?.notesId == "r1")
        #expect(saved?.syncedHash == ContentHash.of("From phone\nbody"))
    }

    @Test func aConflictKeepsBothTextsAndCreatesACopy() throws {
        let synced = ContentHash.of("original")
        let (engine, store, _, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "mac edit", syncedHash: synced)],
            remote: [RemoteNote(id: "r1", title: "phone edit", text: "phone edit",
                                modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().conflicts == 1)
        let texts = try store.all().map(\.text)
        #expect(texts.contains("mac edit"), "the local edit must survive")
        #expect(texts.contains { $0.contains("phone edit") }, "the remote edit must survive too")
        #expect(texts.count == 2)
    }

    @Test func theConflictCopyIsLabelledSoItIsObvious() throws {
        let (engine, store, _, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "mine",
                         syncedHash: ContentHash.of("base"))],
            remote: [RemoteNote(id: "r1", title: "theirs", text: "theirs", modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try engine.runOnce()
        let copy = try store.all().first { $0.id != "l1" }
        #expect(copy?.text.contains("conflict") == true)
        #expect(copy?.notesId == nil, "the copy must not claim the original's Notes id")
    }

    @Test func aConflictSettlesInsteadOfSpawningACopyEveryPoll() throws {
        // Without this the app would produce one "(conflict ...)" note per poll
        // for ever, which is worse than losing the edit.
        let (engine, store, _, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "mac edit",
                         syncedHash: ContentHash.of("original"))],
            remote: [RemoteNote(id: "r1", title: "phone edit", text: "phone edit",
                                modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().conflicts == 1)
        let afterFirst = try store.all().count

        #expect(try engine.runOnce().conflicts == 0, "a second pass must not re-flag it")
        #expect(try engine.runOnce().conflicts == 0, "nor a third")
        #expect(try store.all().count == afterFirst, "no extra copies may appear")
    }

    @Test func afterAConflictTheLocalEditReachesNotes() throws {
        // Keeping both texts is only half the promise. The version the user was
        // actually looking at has to end up in Apple Notes too.
        let (engine, _, bridge, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "mac edit",
                         syncedHash: ContentHash.of("original"))],
            remote: [RemoteNote(id: "r1", title: "phone edit", text: "phone edit",
                                modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try engine.runOnce()
        _ = try engine.runOnce()
        let remoteTexts = bridge.current.map(\.text)
        #expect(remoteTexts.contains("mac edit"))
        #expect(remoteTexts.contains { $0.contains("phone edit") })
    }

    @Test func aFormattingOnlyChangeIsStillPushed() throws {
        // The plain text is identical, so no hash can see this. Only the flag can.
        let text = "make this bold"
        let (engine, store, bridge, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: text,
                         styleRuns: [TextStyleRun(location: 5, length: 4, bold: true)],
                         styleDirty: true,
                         syncedHash: ContentHash.of(text))],
            remote: [RemoteNote(id: "r1", title: text, text: text,
                                body: NoteHTML.toHTML(text), modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().pushed == 1)
        #expect(bridge.current.first?.body.contains("<b>this</b>") == true)
        #expect(try store.find(id: "l1")?.styleDirty == false)
    }

    @Test func aFormattingOnlyPushSettlesAndDoesNotRepeat() throws {
        let text = "make this bold"
        let (engine, _, dir) = try {
            let (e, s, _, d) = try makeEngine(
                notes: [Note(id: "l1", notesId: "r1", text: text,
                             styleRuns: [TextStyleRun(location: 5, length: 4, bold: true)],
                             styleDirty: true, syncedHash: ContentHash.of(text))],
                remote: [RemoteNote(id: "r1", title: text, text: text,
                                    body: NoteHTML.toHTML(text), modifiedAt: Date())]
            )
            return (e, s, d)
        }()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try engine.runOnce()
        #expect(try engine.runOnce() == SyncReport(), "the second pass must do nothing")
    }

    @Test func formattingComesBackWhenARemoteNoteIsPulled() throws {
        let text = "bold word here"
        let rich = RichText(text: text,
                            runs: [TextStyleRun(location: 0, length: 4, bold: true)])
        let (engine, store, _, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "old",
                         syncedHash: ContentHash.of("old"))],
            remote: [RemoteNote(id: "r1", title: text, text: text,
                                body: NoteHTML.toHTML(rich), modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().pulled == 1)
        #expect(try store.find(id: "l1")?.styleRuns
                == [TextStyleRun(location: 0, length: 4, bold: true)])
    }

    @Test func formattingComesAlongWhenARemoteNoteIsAdopted() throws {
        let rich = RichText(text: "under me",
                            runs: [TextStyleRun(location: 0, length: 5, underline: true)])
        let (engine, store, _, dir) = try makeEngine(
            remote: [RemoteNote(id: "r1", title: "under me", text: "under me",
                                body: NoteHTML.toHTML(rich), modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try engine.runOnce()
        #expect(try store.find(notesId: "r1")?.styleRuns
                == [TextStyleRun(location: 0, length: 5, underline: true)])
    }

    @Test func aNoteWithFormattingSyncsWithoutLooping() throws {
        let rich = RichText(text: "keep this steady",
                            runs: [TextStyleRun(location: 5, length: 4, italic: true)])
        var note = Note(id: "l1", text: rich.text)
        note.styleRuns = rich.runs
        let (engine, _, bridge, dir) = try makeEngine(notes: [note])
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try engine.runOnce()
        #expect(try engine.runOnce() == SyncReport())
        #expect(try engine.runOnce() == SyncReport())
        #expect(bridge.current.first?.body.contains("<i>this</i>") == true)
    }

    @Test func remoteEditIsPulledIntoTheLocalCache() throws {
        let (engine, store, _, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "old",
                         syncedHash: ContentHash.of("old"))],
            remote: [RemoteNote(id: "r1", title: "new", text: "new", modifiedAt: Date())]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().pulled == 1)
        #expect(try store.find(id: "l1")?.text == "new")
    }

    @Test func aNoteThatVanishedFromNotesIsArchivedAndItsTextKept() throws {
        let (engine, store, _, dir) = try makeEngine(
            notes: [Note(id: "l1", notesId: "r1", text: "deleted on the phone",
                         syncedHash: ContentHash.of("deleted on the phone"))]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(try engine.runOnce().archived == 1)
        let saved = try store.find(id: "l1")
        #expect(saved?.isArchived == true)
        #expect(saved?.text == "deleted on the phone", "archiving must never lose the text")
    }

    @Test func aBridgeFailureLeavesTheLocalCacheUntouched() throws {
        let (engine, store, bridge, dir) = try makeEngine(notes: [Note(id: "l1", text: "hello")])
        defer { try? FileManager.default.removeItem(at: dir) }
        bridge.failWith = .notAuthorised

        #expect(throws: NotesBridgeError.self) { try engine.runOnce() }
        #expect(try store.find(id: "l1")?.notesId == nil)
        #expect(try store.find(id: "l1")?.text == "hello")
    }

    @Test func colorsArePersistedToTheSidecarUnderTheNotesId() throws {
        let sidecar = FakeSidecarStore()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NoteStore(path: dir.appendingPathComponent("n.sqlite").path)
        try store.upsert(Note(id: "l1", text: "coloured", color: .blue))
        let engine = SyncEngine(store: store, bridge: FakeNotesBridge(), sidecar: sidecar,
                                account: "iCloud", folder: "StickyDock")

        _ = try engine.runOnce()
        let notesId = try #require(try store.find(id: "l1")?.notesId)
        #expect(sidecar.load().entries[notesId]?.color == .blue)
    }

    @Test func anAdoptedNoteTakesItsColourFromTheSidecar() throws {
        // This is what makes a colour set on one Mac show up on the other.
        let sidecar = FakeSidecarStore()
        sidecar.save(Sidecar(version: 1, entries: [
            "r1": SidecarEntry(color: .purple, sortIndex: 7, updatedAt: Date()),
        ]))
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stickydock-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try NoteStore(path: dir.appendingPathComponent("n.sqlite").path)
        let engine = SyncEngine(
            store: store,
            bridge: FakeNotesBridge(notes: [
                RemoteNote(id: "r1", title: "x", text: "x", modifiedAt: Date()),
            ]),
            sidecar: sidecar, account: "iCloud", folder: "StickyDock"
        )

        _ = try engine.runOnce()
        #expect(try store.find(notesId: "r1")?.color == .purple)
        #expect(try store.find(notesId: "r1")?.sortIndex == 7)
    }
}
