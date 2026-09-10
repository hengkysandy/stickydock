import Foundation

/// The per-note state that Apple Notes has nowhere to put.
public struct SidecarEntry: Codable, Equatable, Sendable {
    public var color: NoteColor
    public var sortIndex: Int
    public var updatedAt: Date

    public init(color: NoteColor, sortIndex: Int, updatedAt: Date) {
        self.color = color
        self.sortIndex = sortIndex
        self.updatedAt = updatedAt
    }
}

/// Keyed by Apple Notes id, so the entries mean the same thing on every Mac.
public struct Sidecar: Codable, Equatable, Sendable {
    public var version: Int
    public var entries: [String: SidecarEntry]

    public init(version: Int = 1, entries: [String: SidecarEntry] = [:]) {
        self.version = version
        self.entries = entries
    }

    public static let empty = Sidecar()
}

public protocol SidecarStoring: Sendable {
    func load() -> Sidecar
    func save(_ sidecar: Sidecar)
    var isAvailable: Bool { get }
}

/// Carries note colours and ordering between Macs through iCloud Drive.
///
/// Apple Notes has no custom metadata field, so a colour cannot ride along with
/// the note. Three options were weighed. Keeping colours only in the local
/// database would strand them on one Mac. Encoding a marker line into the note
/// body would put visible junk on the iPhone. A sidecar file is invisible on the
/// phone and still syncs Mac to Mac, so that is what this is.
///
/// **No Apple Developer entitlement is involved.** The paid iCloud entitlement
/// applies to sandboxed apps using a private ubiquity container. StickyDock is
/// not sandboxed, so this is an ordinary directory that the iCloud daemon syncs
/// like any folder made in Finder.
///
/// **Every failure is swallowed on purpose.** If iCloud Drive is missing or
/// unwritable, colours fall back to the local database and the app carries on.
/// The note text lives in Apple Notes, so nothing here is ever the only copy of
/// anything. Crashing over a lost colour would be the wrong trade.
public final class SidecarStore: SidecarStoring, @unchecked Sendable {
    // @unchecked Sendable is safe: the only stored property is an immutable URL,
    // and every write goes through an atomic file replacement.
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("sidecar.json") }

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs/StickyDock`, created if
    /// missing. Returns nil when iCloud Drive is switched off, in which case the
    /// caller should carry on with local-only colours.
    public static func iCloudDirectory() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            .appendingPathComponent("StickyDock")
        guard FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().path) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    public var isAvailable: Bool {
        FileManager.default.isWritableFile(atPath: directory.path)
    }

    public func load() -> Sidecar {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Sidecar.self, from: data)) ?? .empty
    }

    public func save(_ sidecar: Sidecar) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sidecar) else { return }
        // .atomic matters: iCloud watches this directory, and a half-written file
        // would sync to the other Mac and decode as nothing.
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Field-level last-write-wins, per note.
    ///
    /// The file is small and rarely written, so a genuine simultaneous edit is
    /// unlikely, and the cost of getting one wrong is a note showing the wrong
    /// colour. That does not justify a real merge algorithm.
    public static func merge(_ a: Sidecar, _ b: Sidecar) -> Sidecar {
        var entries = a.entries
        for (key, incoming) in b.entries {
            if let existing = entries[key], existing.updatedAt >= incoming.updatedAt {
                continue
            }
            entries[key] = incoming
        }
        return Sidecar(version: max(a.version, b.version), entries: entries)
    }
}
