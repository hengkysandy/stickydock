import Foundation

/// Something typed but not yet written to the database.
///
/// Writes are debounced, so for up to one debounce interval the database is
/// behind the keyboard. Anything that reloads from the database during that
/// window, a sync finishing or the debounced save itself, would otherwise
/// republish an older version of the note. The editor then sees a value that
/// differs from what is on screen and rewrites itself from it, which looks like
/// the note blinking and loses every character typed since the last save.
///
/// So a reload is never allowed to move the note being typed into backwards:
/// whatever is unsaved is laid back over the top.
public struct UnsavedEdit: Equatable, Sendable {
    public let noteId: String
    public let rich: RichText

    public init(noteId: String, rich: RichText) {
        self.noteId = noteId
        self.rich = rich
    }

    /// Lays this edit over a list just read from the database.
    ///
    /// Only the text and its formatting are carried over. Everything else on the
    /// note, `notesId` and `syncedHash` especially, is whatever the database now
    /// holds, because a sync may well have just set them.
    public func applied(to notes: [Note]) -> [Note] {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return notes }
        guard notes[index].rich != rich else { return notes }
        var updated = notes
        updated[index].rich = rich
        return updated
    }
}
