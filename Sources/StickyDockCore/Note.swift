import Foundation

/// The colour of a sticky note.
///
/// Apple Notes has no custom metadata field, so a note's colour cannot travel
/// with the note itself. It lives in the local database and, when iCloud Drive
/// is reachable, in a sidecar file. See `SidecarStore`.
public enum NoteColor: String, Codable, CaseIterable, Sendable {
    case yellow, pink, blue, green, purple, grey
}

/// One sticky note, as StickyDock holds it locally.
public struct Note: Codable, Equatable, Identifiable, Sendable {
    /// Local identity. Stable for the life of the note, even before it reaches
    /// Apple Notes.
    public var id: String
    /// The Apple Notes id, an `x-coredata://` URI. Nil until the note has been
    /// pushed for the first time.
    public var notesId: String?
    public var text: String
    public var color: NoteColor
    public var createdAt: Date
    public var updatedAt: Date
    /// Archived, not deleted. Archived notes stay searchable and recoverable.
    public var archivedAt: Date?
    public var sortIndex: Int
    /// The content hash as of the last successful sync in either direction.
    /// This, not a timestamp, is what stops a push from looking like a remote
    /// change on the next poll. Nil means never synced.
    public var syncedHash: String?

    public var isArchived: Bool { archivedAt != nil }
    public var title: String { NoteHTML.title(of: text) }

    public init(
        id: String = UUID().uuidString,
        notesId: String? = nil,
        text: String = "",
        color: NoteColor = .yellow,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        sortIndex: Int = 0,
        syncedHash: String? = nil
    ) {
        self.id = id
        self.notesId = notesId
        self.text = text
        self.color = color
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.sortIndex = sortIndex
        self.syncedHash = syncedHash
    }
}
