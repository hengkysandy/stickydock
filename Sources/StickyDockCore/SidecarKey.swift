import Foundation

/// The name a note goes by in the sidecar file.
///
/// It cannot be the note's Apple Notes `id`. That is a Core Data URI built from
/// the local store's UUID and a local row number, so the same iCloud note has a
/// different one on every Mac. Keying on it meant the two Macs never recognised
/// each other's entries, and each pruned the other's on every sync.
///
/// The creation date is the one thing Apple Notes carries between machines
/// unchanged, so that is the key.
public enum SidecarKey {

    /// Apple Notes reports creation dates to the second, so two notes made in
    /// the same second would collide. `ambiguous` below is how that is handled.
    public static func of(_ note: RemoteNote) -> String {
        formatter.string(from: note.createdAt)
    }

    /// Keys shared by more than one note in the folder.
    ///
    /// Anything in here is skipped rather than guessed at. Leaving a note its
    /// local colour is a smaller error than painting it with another note's.
    public static func ambiguous(in remote: [RemoteNote]) -> Set<String> {
        var seen: Set<String> = []
        var clashing: Set<String> = []
        for note in remote {
            let key = of(note)
            if !seen.insert(key).inserted { clashing.insert(key) }
        }
        return clashing
    }

    /// Usable keys for a folder, one per note, with the ambiguous ones removed.
    public static func map(for remote: [RemoteNote]) -> [String: String] {
        let clashing = ambiguous(in: remote)
        var byNotesId: [String: String] = [:]
        for note in remote {
            let key = of(note)
            guard !clashing.contains(key) else { continue }
            byNotesId[note.id] = key
        }
        return byNotesId
    }

    private static var formatter: ISO8601DateFormatter {
        // Computed, not stored: ISO8601DateFormatter is not Sendable.
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }
}
