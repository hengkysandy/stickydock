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
    /// True when the note has been dragged out of the dock and lives in its own
    /// window on the desktop.
    ///
    /// This and the frame below are per-Mac display state, deliberately kept out
    /// of the iCloud sidecar: screen layouts differ between machines, so a window
    /// position is not something that should travel.
    public var isDetached: Bool
    public var frameX: Double?
    public var frameY: Double?
    public var frameWidth: Double?
    public var frameHeight: Double?

    /// Bold, italic and underline ranges, stored as JSON.
    ///
    /// Held as an encoded string rather than a typed column because SQLite has
    /// nowhere to put an array, and this is never queried, only read whole.
    public var styleRunsJSON: String?
    /// Set when only the formatting changed.
    ///
    /// Sync decisions are made on the hash of the plain text, deliberately: the
    /// formatting recovered from a note body is best-effort, and hashing it
    /// would risk a sync loop. A formatting-only edit changes no plain text, so
    /// it needs this flag to be noticed at all.
    public var styleDirty: Bool

    /// The content hash as of the last successful sync in either direction.
    /// This, not a timestamp, is what stops a push from looking like a remote
    /// change on the next poll. Nil means never synced.
    public var syncedHash: String?

    public var isArchived: Bool { archivedAt != nil }
    public var title: String { NoteHTML.title(of: text) }

    public var styleRuns: [TextStyleRun] {
        get {
            guard let styleRunsJSON, let data = styleRunsJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([TextStyleRun].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) else {
                styleRunsJSON = nil
                return
            }
            styleRunsJSON = String(decoding: data, as: UTF8.self)
        }
    }

    public var rich: RichText {
        get { RichText(text: text, runs: styleRuns) }
        set {
            text = newValue.text
            styleRuns = newValue.runs
        }
    }

    /// The saved window rectangle, or nil if this note has never been detached.
    public var frame: NoteFrame? {
        get {
            guard let frameX, let frameY, let frameWidth, let frameHeight else { return nil }
            return NoteFrame(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        }
        set {
            frameX = newValue?.x
            frameY = newValue?.y
            frameWidth = newValue?.width
            frameHeight = newValue?.height
        }
    }

    public init(
        id: String = UUID().uuidString,
        notesId: String? = nil,
        text: String = "",
        color: NoteColor = .yellow,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil,
        sortIndex: Int = 0,
        isDetached: Bool = false,
        frame: NoteFrame? = nil,
        styleRuns: [TextStyleRun] = [],
        styleDirty: Bool = false,
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
        self.isDetached = isDetached
        self.frameX = frame?.x
        self.frameY = frame?.y
        self.frameWidth = frame?.width
        self.frameHeight = frame?.height
        self.styleRunsJSON = nil
        self.styleDirty = styleDirty
        self.syncedHash = syncedHash
        self.styleRuns = styleRuns
    }
}
