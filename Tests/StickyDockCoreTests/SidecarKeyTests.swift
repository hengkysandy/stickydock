import Foundation
import Testing
@testable import StickyDockCore

@Suite("SidecarKey")
struct SidecarKeyTests {
    private func note(_ id: String, created: TimeInterval) -> RemoteNote {
        RemoteNote(id: id, title: id, text: id,
                   createdAt: Date(timeIntervalSince1970: created), modifiedAt: Date())
    }

    @Test func theKeyIgnoresTheDeviceLocalNoteId() {
        // The same note seen from two Macs: different Core Data URIs, one key.
        let macA = note("x-coredata://AAAA-1111/ICNote/p17", created: 1_789_032_168)
        let macB = note("x-coredata://BBBB-9999/ICNote/p402", created: 1_789_032_168)
        #expect(SidecarKey.of(macA) == SidecarKey.of(macB))
    }

    @Test func differentNotesGetDifferentKeys() {
        #expect(SidecarKey.of(note("a", created: 1_789_032_168))
                != SidecarKey.of(note("b", created: 1_789_032_185)))
    }

    @Test func theKeyIsUtcSoTheMacsAgreeAcrossTimeZones() {
        #expect(SidecarKey.of(note("a", created: 1_789_032_168)).hasSuffix("Z"))
    }

    @Test func twoNotesMadeInTheSameSecondAreFlaggedAmbiguous() {
        // Apple Notes reports creation to the second, so this can happen when
        // several notes are pushed at once.
        let clash = SidecarKey.ambiguous(in: [
            note("a", created: 1_000), note("b", created: 1_000), note("c", created: 2_000),
        ])
        #expect(clash.count == 1)
        #expect(clash.contains(SidecarKey.of(note("a", created: 1_000))))
    }

    @Test func ambiguousNotesAreLeftOutOfTheMapEntirely() {
        // Better to leave both their local colour than paint one with the other's.
        let map = SidecarKey.map(for: [
            note("a", created: 1_000), note("b", created: 1_000), note("c", created: 2_000),
        ])
        #expect(map.keys.sorted() == ["c"])
    }

    @Test func aFolderWithNoClashesMapsEveryNote() {
        let map = SidecarKey.map(for: [
            note("a", created: 1_000), note("b", created: 2_000), note("c", created: 3_000),
        ])
        #expect(map.count == 3)
        #expect(Set(map.values).count == 3)
    }

    @Test func anEmptyFolderIsSafe() {
        #expect(SidecarKey.map(for: []).isEmpty)
        #expect(SidecarKey.ambiguous(in: []).isEmpty)
    }
}
