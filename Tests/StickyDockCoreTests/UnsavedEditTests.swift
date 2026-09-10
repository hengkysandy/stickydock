import Foundation
import Testing
@testable import StickyDockCore

@Suite("UnsavedEdit")
struct UnsavedEditTests {

    @Test func unsavedTextWinsOverWhatTheDatabaseHolds() {
        // The exact shape of the bug: the database has "hello", the user has
        // since typed " world", and a reload lands. The reload must not win.
        let stored = [Note(id: "n", text: "hello")]
        let pending = UnsavedEdit(noteId: "n", rich: RichText(text: "hello world"))
        #expect(pending.applied(to: stored).first?.text == "hello world")
    }

    @Test func everythingExceptTheTextComesFromTheDatabase() {
        // A sync running at the same moment may have just assigned these. Taking
        // them from the editor's stale copy would erase them.
        let stored = [Note(id: "n", notesId: "x-coredata://a/ICNote/p1", text: "hello",
                           syncedHash: "abc")]
        let merged = UnsavedEdit(noteId: "n", rich: RichText(text: "hello world"))
            .applied(to: stored)
        #expect(merged.first?.notesId == "x-coredata://a/ICNote/p1")
        #expect(merged.first?.syncedHash == "abc")
        #expect(merged.first?.text == "hello world")
    }

    @Test func formattingIsCarriedOverToo() {
        let stored = [Note(id: "n", text: "make this bold")]
        let pending = UnsavedEdit(
            noteId: "n",
            rich: RichText(text: "make this bold",
                           runs: [TextStyleRun(location: 5, length: 4, bold: true)])
        )
        #expect(pending.applied(to: stored).first?.styleRuns
                == [TextStyleRun(location: 5, length: 4, bold: true)])
    }

    @Test func anEditForANoteThatIsNotInTheListChangesNothing() {
        let stored = [Note(id: "other", text: "untouched")]
        let merged = UnsavedEdit(noteId: "missing", rich: RichText(text: "x")).applied(to: stored)
        #expect(merged == stored)
    }

    @Test func anEditThatMatchesTheDatabaseIsANoOp() {
        // Returning the same array matters: a fresh one would republish the list
        // and make every view rebuild for nothing.
        let stored = [Note(id: "n", text: "same")]
        let merged = UnsavedEdit(noteId: "n", rich: RichText(text: "same")).applied(to: stored)
        #expect(merged == stored)
    }

    @Test func onlyTheEditedNoteIsTouched() {
        let stored = [
            Note(id: "a", text: "first"),
            Note(id: "b", text: "second"),
            Note(id: "c", text: "third"),
        ]
        let merged = UnsavedEdit(noteId: "b", rich: RichText(text: "second edited"))
            .applied(to: stored)
        #expect(merged.map(\.text) == ["first", "second edited", "third"])
    }

    @Test func anEmptyListIsSafe() {
        #expect(UnsavedEdit(noteId: "n", rich: RichText(text: "x")).applied(to: []).isEmpty)
    }
}
