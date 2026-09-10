import Foundation

/// One decision about one note.
public enum SyncAction: Equatable, Sendable {
    case none(noteId: String)
    /// Local note that has never reached Apple Notes.
    case create(noteId: String)
    /// Local text is ahead. Send it.
    case push(noteId: String)
    /// Apple Notes is ahead. Take it.
    case pull(noteId: String, notesId: String)
    /// A note in the Notes folder that this Mac has never seen.
    case adopt(notesId: String)
    /// Both sides changed to different text. Keep both.
    case conflict(noteId: String, remoteText: String)
    /// It was synced once and is now gone from the Notes folder.
    case archiveLocal(noteId: String)
    /// Archived here, so take it out of the Notes folder but keep the text.
    case deleteRemote(noteId: String, notesId: String)
    /// Deleted here for good. Remove it from Apple Notes, then drop the row.
    /// `notesId` is nil when the note never reached Apple Notes, or is already
    /// gone from the folder.
    case purge(noteId: String, notesId: String?)
    /// Archived here, but edited on another device afterwards. Bring it back.
    case restore(noteId: String, notesId: String)
    /// Both sides already agree. Just record the hash.
    case markSynced(noteId: String, hash: String)
}

public struct SyncReport: Equatable, Sendable {
    public var pushed = 0
    public var pulled = 0
    public var created = 0
    public var adopted = 0
    public var conflicts = 0
    public var archived = 0
    public var deletedRemotely = 0
    public var restored = 0

    public init() {}

    public var isEmpty: Bool { self == SyncReport() }

    public var summary: String {
        var parts: [String] = []
        if created > 0  { parts.append("\(created) created") }
        if pushed > 0   { parts.append("\(pushed) sent") }
        if pulled > 0   { parts.append("\(pulled) received") }
        if adopted > 0  { parts.append("\(adopted) picked up") }
        if restored > 0 { parts.append("\(restored) restored") }
        if archived > 0 { parts.append("\(archived) archived") }
        if deletedRemotely > 0 { parts.append("\(deletedRemotely) removed") }
        if conflicts > 0 { parts.append("\(conflicts) conflict\(conflicts == 1 ? "" : "s")") }
        return parts.isEmpty ? "Up to date" : parts.joined(separator: ", ")
    }
}

/// Mirrors the local cache and one Apple Notes folder into each other.
///
/// The design rule that shapes everything here: **never lose text.** When the
/// two sides disagree, both versions are kept and the user decides. A sticky
/// note app has no business guessing which edit mattered more.
public final class SyncEngine: @unchecked Sendable {
    // @unchecked Sendable is safe: every stored property is a let, and each of
    // the three collaborators serialises its own access internally.
    private let store: NoteStoring
    private let bridge: NotesBridging
    private let sidecar: SidecarStoring
    private let account: String
    private let folder: String

    public init(
        store: NoteStoring,
        bridge: NotesBridging,
        sidecar: SidecarStoring,
        account: String,
        folder: String
    ) {
        self.store = store
        self.bridge = bridge
        self.sidecar = sidecar
        self.account = account
        self.folder = folder
    }

    // MARK: - The decision table

    /// Pure. No database, no Notes.app, no clock. Every rule in the design
    /// document's table is one branch here and one test over there.
    ///
    /// Hashes decide, never timestamps. Pushing to Apple Notes bumps that note's
    /// modification date, so a timestamp comparison would read our own write as
    /// a remote change on the very next poll and push it back for ever.
    public static func plan(local: [Note], remote: [RemoteNote]) -> [SyncAction] {
        var remoteById: [String: RemoteNote] = [:]
        for note in remote { remoteById[note.id] = note }

        var actions: [SyncAction] = []
        var claimed = Set<String>()
        func append(_ action: SyncAction) { actions.append(action) }

        for note in local {
            if note.isDeleted {
                // Claim the id first. Without this the very same pass would see
                // the note still sitting in Apple Notes, call it unknown, and
                // adopt it straight back. That is exactly how deleted notes kept
                // coming back.
                if let notesId = note.notesId {
                    claimed.insert(notesId)
                    let stillThere = remoteById[notesId] != nil
                    actions.append(.purge(noteId: note.id, notesId: stillThere ? notesId : nil))
                } else {
                    actions.append(.purge(noteId: note.id, notesId: nil))
                }
                continue
            }

            guard let notesId = note.notesId else {
                // Never pushed. Create it, unless it is archived or still blank.
                if !note.isArchived && !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    actions.append(.create(noteId: note.id))
                }
                continue
            }

            guard let remoteNote = remoteById[notesId] else {
                // It had a home in Notes and no longer does.
                if !note.isArchived {
                    actions.append(.archiveLocal(noteId: note.id))
                }
                continue
            }
            claimed.insert(notesId)

            let localHash = ContentHash.of(note.text)
            let remoteHash = ContentHash.of(remoteNote.text)

            if note.isArchived {
                if remoteHash != (note.syncedHash ?? "") {
                    // Edited elsewhere after being archived here. Deleting it
                    // would throw away work that was just done.
                    actions.append(.restore(noteId: note.id, notesId: notesId))
                } else {
                    actions.append(.deleteRemote(noteId: note.id, notesId: notesId))
                }
                continue
            }

            let base = note.syncedHash ?? ""
            let localChanged = localHash != base
            let remoteChanged = remoteHash != base

            switch (localChanged, remoteChanged) {
            case (false, false):
                // The plain text agrees, but the formatting may not have been
                // sent yet. Hashes cannot see that, so the flag has to.
                append(note.styleDirty ? .push(noteId: note.id) : .none(noteId: note.id))
            case (true, false):
                actions.append(.push(noteId: note.id))
            case (false, true):
                actions.append(.pull(noteId: note.id, notesId: notesId))
            case (true, true):
                if localHash == remoteHash {
                    // Both moved to the same text, or the cache was rebuilt from
                    // scratch. Agreement is not a conflict.
                    actions.append(.markSynced(noteId: note.id, hash: localHash))
                } else {
                    actions.append(.conflict(noteId: note.id, remoteText: remoteNote.text))
                }
            }
        }

        for remoteNote in remote where !claimed.contains(remoteNote.id) {
            actions.append(.adopt(notesId: remoteNote.id))
        }
        return actions
    }

    // MARK: - Applying it

    /// One full sync pass. Throws only if Apple Notes itself is unreachable; a
    /// failure part-way leaves the local cache exactly as it was for the notes
    /// not yet handled, so the next pass picks up where this one stopped.
    @discardableResult
    public func runOnce() throws -> SyncReport {
        try bridge.ensureFolder(account: account, folder: folder)
        let remote = try bridge.list(account: account, folder: folder)
        let local = try store.all()
        var sheet = SidecarStore.merge(sidecar.load(), Sidecar.empty)
        var report = SyncReport()

        for action in Self.plan(local: local, remote: remote) {
            switch action {
            case .none:
                break

            case .create(let noteId):
                guard var note = try store.find(id: noteId) else { break }
                let created = try bridge.create(
                    account: account, folder: folder, rich: note.rich
                )
                note.notesId = created.id
                note.syncedHash = ContentHash.of(created.text)
                note.styleDirty = false
                try store.upsert(note)
                sheet.entries[created.id] = SidecarEntry(
                    color: note.color, sortIndex: note.sortIndex, updatedAt: Date()
                )
                report.created += 1

            case .push(let noteId):
                guard var note = try store.find(id: noteId), let notesId = note.notesId else { break }
                let updated = try bridge.update(
                    account: account, folder: folder, id: notesId, rich: note.rich
                )
                note.syncedHash = ContentHash.of(updated.text)
                note.styleDirty = false
                try store.upsert(note)
                sheet.entries[notesId] = SidecarEntry(
                    color: note.color, sortIndex: note.sortIndex, updatedAt: Date()
                )
                report.pushed += 1

            case .pull(let noteId, let notesId):
                guard var note = try store.find(id: noteId),
                      let incoming = remote.first(where: { $0.id == notesId }) else { break }
                note.text = incoming.text
                note.styleRuns = incoming.styleRuns
                note.styleDirty = false
                note.updatedAt = incoming.modifiedAt
                note.syncedHash = ContentHash.of(incoming.text)
                try store.upsert(note)
                report.pulled += 1

            case .adopt(let notesId):
                guard let incoming = remote.first(where: { $0.id == notesId }) else { break }
                let entry = sheet.entries[notesId]
                try store.upsert(Note(
                    notesId: incoming.id,
                    text: incoming.text,
                    color: entry?.color ?? .yellow,
                    createdAt: incoming.modifiedAt,
                    updatedAt: incoming.modifiedAt,
                    sortIndex: entry?.sortIndex ?? (try store.nextSortIndex()),
                    styleRuns: incoming.styleRuns,
                    syncedHash: ContentHash.of(incoming.text)
                ))
                report.adopted += 1

            case .conflict(let noteId, let remoteText):
                guard var note = try store.find(id: noteId) else { break }
                // Both versions survive. The local note keeps its Notes id and
                // will be pushed on the next pass; the copy is a fresh local
                // note with no id of its own, so it cannot overwrite anything.
                let stamp = Self.conflictStamp.string(from: Date())
                try store.upsert(Note(
                    text: "\(note.title) (conflict \(stamp))\n\n\(remoteText)",
                    color: note.color,
                    sortIndex: try store.nextSortIndex()
                ))
                // Treat the local text as the winner for the base hash, so the
                // next pass pushes it instead of flagging the same conflict again.
                note.syncedHash = ContentHash.of(remoteText)
                try store.upsert(note)
                report.conflicts += 1

            case .purge(let noteId, let notesId):
                if let notesId {
                    try bridge.delete(account: account, folder: folder, id: notesId)
                    sheet.entries[notesId] = nil
                }
                try store.delete(id: noteId)
                report.deletedRemotely += 1

            case .archiveLocal(let noteId):
                try store.archive(id: noteId, at: Date())
                report.archived += 1

            case .deleteRemote(let noteId, let notesId):
                try bridge.delete(account: account, folder: folder, id: notesId)
                if var note = try store.find(id: noteId) {
                    // Keep the text. Only the link to Notes goes away.
                    note.notesId = nil
                    note.syncedHash = nil
                    try store.upsert(note)
                }
                sheet.entries[notesId] = nil
                report.deletedRemotely += 1

            case .restore(let noteId, let notesId):
                guard var note = try store.find(id: noteId),
                      let incoming = remote.first(where: { $0.id == notesId }) else { break }
                note.archivedAt = nil
                note.text = incoming.text
                note.styleRuns = incoming.styleRuns
                note.updatedAt = incoming.modifiedAt
                note.syncedHash = ContentHash.of(incoming.text)
                try store.upsert(note)
                report.restored += 1

            case .markSynced(let noteId, let hash):
                guard var note = try store.find(id: noteId) else { break }
                note.syncedHash = hash
                try store.upsert(note)
            }
        }

        // Every note that lives in Apple Notes gets an entry, not only the ones
        // this pass happened to create or push. Colour is not part of the note's
        // text, so changing it triggers no sync action at all, and adopted notes
        // were never written here either: the file ended up describing a
        // fraction of the notes, with stale colours for the rest, and none of it
        // reached the other Mac.
        let live = try store.all().filter { !$0.isDeleted }
        for note in live {
            guard let notesId = note.notesId else { continue }
            guard let existing = sheet.entries[notesId] else {
                sheet.entries[notesId] = SidecarEntry(
                    color: note.color, sortIndex: note.sortIndex, updatedAt: note.updatedAt
                )
                continue
            }
            let differs = existing.color != note.color || existing.sortIndex != note.sortIndex
            // Only overwrite when this Mac's version is genuinely newer, or a
            // colour picked on the other Mac would be undone on every poll.
            if differs, note.updatedAt > existing.updatedAt {
                sheet.entries[notesId] = SidecarEntry(
                    color: note.color, sortIndex: note.sortIndex, updatedAt: note.updatedAt
                )
            }
        }

        let liveIds = Set(live.compactMap(\.notesId))
        sheet.entries = sheet.entries.filter { liveIds.contains($0.key) }
        sidecar.save(sheet)
        return report
    }

    private static var conflictStamp: DateFormatter {
        // Computed, not stored: DateFormatter is not Sendable.
        let f = DateFormatter()
        // A fixed format needs a fixed locale, or the user's 12/24 hour setting
        // and calendar can rewrite it into something else.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }
}
