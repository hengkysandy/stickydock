import Foundation
import Testing
@testable import StickyDockCore

@Suite("DetachedFrame")
struct DetachedFrameTests {
    private let screen = NoteFrame(x: 0, y: 0, width: 1470, height: 900)

    @Test func aFrameFullyOnScreenIsLeftAlone() {
        let frame = NoteFrame(x: 100, y: 100, width: 240, height: 200)
        #expect(DetachedFrame.clamp(frame, toAnyOf: [screen]) == frame)
    }

    @Test func aFrameOffTheRightEdgeIsPulledBack() {
        let frame = NoteFrame(x: 1400, y: 100, width: 240, height: 200)
        let clamped = DetachedFrame.clamp(frame, toAnyOf: [screen])
        #expect(clamped.x + clamped.width <= screen.width)
        #expect(clamped.width == 240, "clamping must move a window, never resize it")
    }

    @Test func aFrameOffTheLeftEdgeIsPulledBack() {
        let clamped = DetachedFrame.clamp(
            NoteFrame(x: -300, y: 100, width: 240, height: 200), toAnyOf: [screen]
        )
        #expect(clamped.x >= 0)
    }

    @Test func aFrameOnADisplayThatIsGoneComesBackToTheMainOne() {
        // Unplugging a second monitor must not strand a note where it cannot be
        // reached. This is the whole reason the function exists.
        let stranded = NoteFrame(x: 3000, y: 1400, width: 240, height: 200)
        let clamped = DetachedFrame.clamp(stranded, toAnyOf: [screen])
        #expect(clamped.x >= 0 && clamped.x + clamped.width <= screen.width)
        #expect(clamped.y >= 0 && clamped.y + clamped.height <= screen.height)
    }

    @Test func aFrameOnASecondDisplayIsLeftAloneWhenThatDisplayIsStillThere() {
        let second = NoteFrame(x: 1470, y: 0, width: 1920, height: 1080)
        let frame = NoteFrame(x: 2000, y: 300, width: 240, height: 200)
        #expect(DetachedFrame.clamp(frame, toAnyOf: [screen, second]) == frame)
    }

    @Test func aWindowLargerThanTheScreenIsShrunkToFit() {
        let huge = NoteFrame(x: 0, y: 0, width: 3000, height: 2000)
        let clamped = DetachedFrame.clamp(huge, toAnyOf: [screen])
        #expect(clamped.width <= screen.width)
        #expect(clamped.height <= screen.height)
    }

    @Test func aFrameIsNeverShrunkBelowTheMinimumUsableSize() {
        let tiny = NoteFrame(x: 10, y: 10, width: 20, height: 15)
        let clamped = DetachedFrame.clamp(tiny, toAnyOf: [screen])
        #expect(clamped.width >= DetachedFrame.minimumSize.width)
        #expect(clamped.height >= DetachedFrame.minimumSize.height)
    }

    @Test func thereIsNoEmptyScreenListCrash() {
        let frame = NoteFrame(x: 10, y: 10, width: 240, height: 200)
        #expect(DetachedFrame.clamp(frame, toAnyOf: []) == frame)
    }

    @Test func theDefaultFrameCentresOnThePointer() {
        let frame = DetachedFrame.defaultFrame(around: NotePoint(x: 500, y: 400))
        #expect(abs(frame.midX - 500) < 0.001)
        #expect(abs(frame.midY - 400) < 0.001)
    }
}
