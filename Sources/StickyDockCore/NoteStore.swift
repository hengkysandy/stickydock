import Foundation
import GRDB

/// What `SyncEngine` needs from local storage. The engine depends on this
/// protocol, never on `NoteStore` itself, so the sync rules can be tested
/// without a database.
public protocol NoteStoring: Sendable {
    func allActive() throws -> [Note]
    /// Active notes that are still in the dock, so the deck does not show a note
    /// that is already sitting on the desktop in its own window.
    func allDocked() throws -> [Note]
    func allDetached() throws -> [Note]
    func all() throws -> [Note]
    func find(id: String) throws -> Note?
    func find(notesId: String) throws -> Note?
    func upsert(_ note: Note) throws
    func delete(id: String) throws
    func archive(id: String, at date: Date) throws
    func search(_ query: String) throws -> [Note]
    func nextSortIndex() throws -> Int
}

extension Note: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "note"
}

/// The local SQLite cache.
///
/// This is a cache, not the source of truth. Apple Notes holds the text that
/// matters. The cache exists so the UI never has to wait on an Apple Event, and
/// so app-only state (colour, sort order, archive) has somewhere to live.
public final class NoteStore: NoteStoring, @unchecked Sendable {
    // @unchecked Sendable is safe here: the only stored property is a GRDB
    // DatabaseQueue, which serialises every access through its own queue.
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        for (name, migrate) in migrationsInOrder {
            migrator.registerMigration(name, migrate: migrate)
        }
        return migrator
    }

    private static var migrationsInOrder: [(String, @Sendable (Database) throws -> Void)] {
        [("v1-notes", v1), ("v2-detached-windows", v2)]
    }

    @Sendable private static func v1(_ db: Database) throws {
        do {
            try db.create(table: "note") { t in
                t.primaryKey("id", .text).notNull()
                t.column("notesId", .text)
                t.column("text", .text).notNull().defaults(to: "")
                t.column("color", .text).notNull().defaults(to: "yellow")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("archivedAt", .datetime)
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("syncedHash", .text)
            }
            try db.create(index: "note_on_notesId", on: "note", columns: ["notesId"])
            try db.create(index: "note_on_archivedAt", on: "note", columns: ["archivedAt"])
        }
    }

    @Sendable private static func v2(_ db: Database) throws {
        do {
            try db.alter(table: "note") { t in
                t.add(column: "isDetached", .boolean).notNull().defaults(to: false)
                t.add(column: "frameX", .double)
                t.add(column: "frameY", .double)
                t.add(column: "frameWidth", .double)
                t.add(column: "frameHeight", .double)
            }
            try db.create(index: "note_on_isDetached", on: "note", columns: ["isDetached"])
        }
    }

    /// Builds a database at the v1 schema and stops, so a test can prove the
    /// v1 to v2 migration works on a real old file rather than a fresh one.
    /// An upgrade that drops every existing note is the worst bug this app could
    /// ship, so it gets a test.
    public static func makeVersionOneDatabaseForTesting(
        path: String, noteId: String, text: String
    ) throws {
        let queue = try DatabaseQueue(path: path)
        var onlyV1 = DatabaseMigrator()
        for (name, migrate) in Self.migrationsInOrder where name == "v1-notes" {
            onlyV1.registerMigration(name, migrate: migrate)
        }
        try onlyV1.migrate(queue)
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note (id, notesId, text, color, createdAt, updatedAt,
                                      archivedAt, sortIndex, syncedHash)
                    VALUES (?, NULL, ?, 'yellow', ?, ?, NULL, 0, NULL)
                    """,
                arguments: [noteId, text, Date(), Date()]
            )
        }
    }

    // MARK: - Reads

    public func allActive() throws -> [Note] {
        try dbQueue.read { db in
            try Note.filter(Column("archivedAt") == nil)
                .order(Column("sortIndex").asc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func allDocked() throws -> [Note] {
        try dbQueue.read { db in
            try Note.filter(Column("archivedAt") == nil && Column("isDetached") == false)
                .order(Column("sortIndex").asc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func allDetached() throws -> [Note] {
        try dbQueue.read { db in
            try Note.filter(Column("archivedAt") == nil && Column("isDetached") == true)
                .order(Column("sortIndex").asc)
                .fetchAll(db)
        }
    }

    public func all() throws -> [Note] {
        try dbQueue.read { db in
            try Note.order(Column("sortIndex").asc, Column("updatedAt").desc).fetchAll(db)
        }
    }

    public func find(id: String) throws -> Note? {
        try dbQueue.read { db in try Note.fetchOne(db, key: id) }
    }

    public func find(notesId: String) throws -> Note? {
        try dbQueue.read { db in
            try Note.filter(Column("notesId") == notesId).fetchOne(db)
        }
    }

    /// Case-insensitive substring search over the body, archived notes included.
    ///
    /// `%` and `_` are escaped so a query of "100%" does not turn into a
    /// wildcard that matches every row. Same discipline as parameterised SQL:
    /// user input is never allowed to change what the query means.
    public func search(_ query: String) throws -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try all() }
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try dbQueue.read { db in
            try Note.filter(
                sql: "text LIKE ? ESCAPE '\\'", arguments: ["%\(escaped)%"]
            )
            .order(Column("updatedAt").desc)
            .fetchAll(db)
        }
    }

    public func nextSortIndex() throws -> Int {
        try dbQueue.read { db in
            let max = try Int.fetchOne(db, sql: "SELECT MAX(sortIndex) FROM note")
            return (max ?? -1) + 1
        }
    }

    // MARK: - Writes

    public func upsert(_ note: Note) throws {
        try dbQueue.write { db in try note.save(db) }
    }

    public func delete(id: String) throws {
        _ = try dbQueue.write { db in try Note.deleteOne(db, key: id) }
    }

    public func archive(id: String, at date: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE note SET archivedAt = ?, updatedAt = ? WHERE id = ?",
                arguments: [date, date, id]
            )
        }
    }
}
