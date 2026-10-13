import Foundation

/// The note made when the same note changed in two places between syncs.
///
/// Both versions are kept: the original keeps its place, and the other version
/// becomes a new note titled `<title> (conflict <date>)`. On a 56pt tab that
/// title is cut to the original title, so a conflict copy looked exactly like a
/// duplicate of the note it came from. Knowing which notes are copies lets the
/// dock mark them.
public enum ConflictCopy {
    /// The first line of a new conflict copy.
    public static func title(for original: String, stamp: String) -> String {
        "\(original) (conflict \(stamp))"
    }

    /// The original note's title, if `title` is a conflict copy's.
    public static func originalTitle(of title: String) -> String? {
        guard let match = title.firstMatch(of: pattern) else { return nil }
        return String(match.1)
    }

    // Matches what `title(for:stamp:)` writes, with the stamp from
    // SyncEngine's `conflictStamp` format, `yyyy-MM-dd HH:mm`.
    nonisolated(unsafe) private static let pattern =
        /^(.*) \(conflict \d{4}-\d{2}-\d{2} \d{2}:\d{2}\)$/
}
