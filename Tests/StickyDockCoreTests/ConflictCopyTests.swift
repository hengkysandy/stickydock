import Testing
@testable import StickyDockCore

@Suite("ConflictCopy")
struct ConflictCopyTests {
    @Test func aConflictTitleGivesBackTheOriginal() {
        #expect(ConflictCopy.originalTitle(of: "personal (conflict 2026-10-12 19:04)") == "personal")
    }

    @Test func whatItWritesItCanReadBack() {
        let title = ConflictCopy.title(for: "standup notes", stamp: "2026-01-02 03:04")
        #expect(ConflictCopy.originalTitle(of: title) == "standup notes")
    }

    @Test func anOrdinaryTitleIsNotAConflict() {
        #expect(ConflictCopy.originalTitle(of: "personal") == nil)
    }

    @Test func theWordConflictAloneIsNotEnough() {
        // A note can mention conflicts without being a copy.
        #expect(ConflictCopy.originalTitle(of: "team conflict (resolved)") == nil)
        #expect(ConflictCopy.originalTitle(of: "x (conflict soon)") == nil)
    }

    @Test func aTitleThatItselfHasBracketsStillWorks() {
        #expect(ConflictCopy.originalTitle(of: "a (b) (conflict 2026-10-12 19:04)") == "a (b)")
    }
}
