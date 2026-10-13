import Testing
@testable import StickyDockCore

@Suite("DeckGeometry")
struct DeckGeometryTests {
    /// The real numbers: 82pt tabs, 76pt apart, 60pt of chrome, 470pt floor.
    private func deck(_ count: Int, screen: Double = 818) -> DeckGeometry {
        DeckGeometry.fitting(noteCount: count, tabHeight: 82, preferredPitch: 76,
                             minimumPitch: 26, chrome: 60,
                             minimumHeight: 470, maximumHeight: screen)
    }

    @Test func aSmallDeckKeepsTheUsualHeight() {
        #expect(deck(3) == DeckGeometry(panelHeight: 470, pitch: 76))
    }

    @Test func sixNotesGetAPanelTallEnoughToHoldThem() {
        // The case that bounced: six tabs need 60 + 82 + 5 * 76 = 522 points.
        #expect(deck(6) == DeckGeometry(panelHeight: 522, pitch: 76))
    }

    @Test func theDeckNeverOutgrowsTheScreen() {
        let crowded = deck(20)
        #expect(crowded.panelHeight == 818)
        // Every tab still fits: the last one ends inside the panel.
        #expect(60 + 82 + 19 * crowded.pitch <= 818)
        #expect(crowded.pitch < 76)
    }

    @Test func tabsStopCompressingAtTheMinimumPitch() {
        #expect(deck(200).pitch == 26)
    }

    @Test func anEmptyDeckIsJustTheFloor() {
        #expect(deck(0) == DeckGeometry(panelHeight: 470, pitch: 76))
    }

    @Test func aScreenShorterThanTheFloorWins() {
        // A small display must not get a panel taller than itself.
        #expect(deck(2, screen: 400).panelHeight == 400)
    }

    @Test func oneNoteNeverDividesByZero() {
        #expect(deck(1, screen: 100).pitch == 76)
    }
}
