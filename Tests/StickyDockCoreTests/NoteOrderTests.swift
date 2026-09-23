import Foundation
import Testing
@testable import StickyDockCore

@Suite("NoteOrder")
struct NoteOrderTests {
    private func notes(_ ids: [String]) -> [Note] {
        ids.enumerated().map { Note(id: $1, text: $1, sortIndex: $0) }
    }

    // MARK: - Which slot the drag has reached

    @Test func staysPutUntilHalfATabHasBeenCrossed() {
        // 37 points of a 76 point pitch is not yet half, so nothing moves.
        #expect(NoteOrder.targetIndex(movingFrom: 1, byVerticalDrag: 37, pitch: 76, count: 4) == 1)
        #expect(NoteOrder.targetIndex(movingFrom: 1, byVerticalDrag: 39, pitch: 76, count: 4) == 2)
    }

    @Test func dragsUpwardAsWellAsDown() {
        #expect(NoteOrder.targetIndex(movingFrom: 2, byVerticalDrag: -76, pitch: 76, count: 4) == 1)
        #expect(NoteOrder.targetIndex(movingFrom: 3, byVerticalDrag: -160, pitch: 76, count: 4) == 1)
    }

    @Test func cannotBeDraggedOffEitherEnd() {
        #expect(NoteOrder.targetIndex(movingFrom: 0, byVerticalDrag: -900, pitch: 76, count: 4) == 0)
        #expect(NoteOrder.targetIndex(movingFrom: 3, byVerticalDrag: 900, pitch: 76, count: 4) == 3)
    }

    @Test func nonsenseGeometryIsRefusedRatherThanDividedBy() {
        #expect(NoteOrder.targetIndex(movingFrom: 1, byVerticalDrag: 50, pitch: 0, count: 4) == 1)
        #expect(NoteOrder.targetIndex(movingFrom: 0, byVerticalDrag: 50, pitch: 76, count: 0) == 0)
    }

    // MARK: - The order while dragging

    @Test func movingDownShiftsTheOthersUp() {
        let moved = NoteOrder.moving("a", to: 2, in: notes(["a", "b", "c", "d"]))
        #expect(moved.map(\.id) == ["b", "c", "a", "d"])
    }

    @Test func movingUpShiftsTheOthersDown() {
        let moved = NoteOrder.moving("d", to: 1, in: notes(["a", "b", "c", "d"]))
        #expect(moved.map(\.id) == ["a", "d", "b", "c"])
    }

    @Test func movingNowhereReturnsTheSameListSoNothingRedraws() {
        let original = notes(["a", "b", "c"])
        #expect(NoteOrder.moving("b", to: 1, in: original).map(\.id) == ["a", "b", "c"])
    }

    @Test func anIdThatIsNotThereChangesNothing() {
        let original = notes(["a", "b", "c"])
        #expect(NoteOrder.moving("zz", to: 0, in: original).map(\.id) == ["a", "b", "c"])
    }

    @Test func aTargetBeyondTheEndsIsClamped() {
        #expect(NoteOrder.moving("a", to: 99, in: notes(["a", "b", "c"])).map(\.id) == ["b", "c", "a"])
        #expect(NoteOrder.moving("c", to: -5, in: notes(["a", "b", "c"])).map(\.id) == ["c", "a", "b"])
    }

    // MARK: - Writing it down

    @Test func onlyTheNotesThatMovedAreWrittenBack() {
        // a keeps index 0, so only b and c changed.
        let displayed = [
            Note(id: "a", text: "a", sortIndex: 0),
            Note(id: "b", text: "b", sortIndex: 2),
            Note(id: "c", text: "c", sortIndex: 1),
        ]
        let changed = NoteOrder.reindexed(displayed)
        #expect(changed.map(\.id) == ["b", "c"])
        #expect(changed.map(\.sortIndex) == [1, 2])
    }

    @Test func anOrderThatDidNotChangeWritesNothing() {
        #expect(NoteOrder.reindexed(notes(["a", "b", "c"])).isEmpty)
    }

    @Test func movedNotesGetAFreshTimestampSoTheOtherMacSeesTheChange() {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let displayed = [
            Note(id: "b", text: "b", updatedAt: Date(timeIntervalSince1970: 1), sortIndex: 1),
            Note(id: "a", text: "a", updatedAt: Date(timeIntervalSince1970: 1), sortIndex: 0),
        ]
        let changed = NoteOrder.reindexed(displayed, now: when)
        #expect(changed.count == 2)
        #expect(changed.allSatisfy { $0.updatedAt == when })
    }

    @Test func aFullRoundTripLandsWhereTheDragPointed() {
        // Drag "a" down two slots and write it: the stored order matches.
        let start = notes(["a", "b", "c", "d"])
        let target = NoteOrder.targetIndex(movingFrom: 0, byVerticalDrag: 152, pitch: 76, count: 4)
        let displayed = NoteOrder.moving("a", to: target, in: start)
        #expect(displayed.map(\.id) == ["b", "c", "a", "d"])
        let changed = NoteOrder.reindexed(displayed)
        var final = displayed
        for note in changed { final[final.firstIndex { $0.id == note.id }!] = note }
        #expect(final.sorted { $0.sortIndex < $1.sortIndex }.map(\.id) == ["b", "c", "a", "d"])
    }

    // MARK: - What the deck draws mid-drag

    @Test func theCarriedTabFollowsThePointer() {
        #expect(NoteOrder.carriedOffset(drag: 40, origin: 1, pitch: 76, count: 4) == 40)
    }

    @Test func theCarriedTabCannotBeDraggedPastTheEndsOfTheDeck() {
        // Four notes, carrying the second one. It can rise 76 and fall 152.
        #expect(NoteOrder.carriedOffset(drag: -500, origin: 1, pitch: 76, count: 4) == -76)
        #expect(NoteOrder.carriedOffset(drag: 500, origin: 1, pitch: 76, count: 4) == 152)
    }

    @Test func anEmptyDeckHasNowhereToCarryAnythingTo() {
        #expect(NoteOrder.carriedOffset(drag: 40, origin: 0, pitch: 76, count: 0) == 0)
    }

    @Test func tabsBetweenTheOriginAndTheTargetStepAside() {
        // Carrying index 0 down to index 2: 1 and 2 move up, 3 stays put.
        #expect(NoteOrder.displacement(atIndex: 0, origin: 0, target: 2, pitch: 76) == 0)
        #expect(NoteOrder.displacement(atIndex: 1, origin: 0, target: 2, pitch: 76) == -76)
        #expect(NoteOrder.displacement(atIndex: 2, origin: 0, target: 2, pitch: 76) == -76)
        #expect(NoteOrder.displacement(atIndex: 3, origin: 0, target: 2, pitch: 76) == 0)
    }

    @Test func carryingATabUpwardsPushesTheOthersDown() {
        #expect(NoteOrder.displacement(atIndex: 0, origin: 3, target: 1, pitch: 76) == 0)
        #expect(NoteOrder.displacement(atIndex: 1, origin: 3, target: 1, pitch: 76) == 76)
        #expect(NoteOrder.displacement(atIndex: 2, origin: 3, target: 1, pitch: 76) == 76)
        #expect(NoteOrder.displacement(atIndex: 3, origin: 3, target: 1, pitch: 76) == 0)
    }

    @Test func nothingMovesUntilTheDragCrossesSomething() {
        for index in 0..<4 {
            #expect(NoteOrder.displacement(atIndex: index, origin: 2, target: 2, pitch: 76) == 0)
        }
    }
}
