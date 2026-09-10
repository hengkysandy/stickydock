import Foundation
@testable import StickyDockCore

/// An in-memory stand-in for Apple Notes.
///
/// Its whole reason to exist: every rule in the sync decision table can be
/// asserted without launching Notes.app, without network, and in microseconds.
final class FakeNotesBridge: NotesBridging, @unchecked Sendable {
    enum Call: Equatable {
        case ensureFolder, list
        case create(text: String)
        case update(id: String, text: String)
        case delete(id: String)
    }

    private let lock = NSLock()
    private var notes: [String: RemoteNote] = [:]
    private var nextId = 1
    private(set) var calls: [Call] = []
    /// Set this to make the next operation fail, for error-path tests.
    var failWith: NotesBridgeError?

    init(notes: [RemoteNote] = []) {
        for note in notes { self.notes[note.id] = note }
    }

    var current: [RemoteNote] {
        lock.withLock { notes.values.sorted { $0.id < $1.id } }
    }

    private func record(_ call: Call) throws {
        lock.withLock { calls.append(call) }
        if let failWith { throw failWith }
    }

    func ensureFolder(account: String, folder: String) throws {
        try record(.ensureFolder)
    }

    func list(account: String, folder: String) throws -> [RemoteNote] {
        try record(.list)
        return current
    }

    func create(account: String, folder: String, text: String, knownIds: [String]) throws -> RemoteNote {
        try record(.create(text: text))
        return lock.withLock {
            let note = RemoteNote(
                id: "x-coredata://fake/ICNote/p\(nextId)",
                title: NoteHTML.title(of: text),
                text: text,
                modifiedAt: Date()
            )
            nextId += 1
            notes[note.id] = note
            return note
        }
    }

    func update(account: String, folder: String, id: String, text: String) throws -> RemoteNote {
        try record(.update(id: id, text: text))
        return try lock.withLock {
            guard let existing = notes[id] else { throw NotesBridgeError.remote("no note \(id)") }
            let note = RemoteNote(id: id, title: NoteHTML.title(of: text),
                                  text: text, modifiedAt: Date())
            notes[id] = note
            _ = existing
            return note
        }
    }

    func delete(account: String, folder: String, id: String) throws {
        try record(.delete(id: id))
        lock.withLock { notes[id] = nil }
    }
}

/// A `SidecarStoring` that keeps everything in memory.
final class FakeSidecarStore: SidecarStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var sidecar = Sidecar.empty
    var isAvailable: Bool = true

    func load() -> Sidecar { lock.withLock { sidecar } }
    func save(_ sidecar: Sidecar) { lock.withLock { self.sidecar = sidecar } }
}
