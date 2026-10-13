import Foundation

/// How tall the open deck is, and how far apart its tabs sit, for a given
/// number of notes.
///
/// The panel used to be a fixed 470 points tall, which holds five tabs. A sixth
/// made the content taller than the window, the hosting view pushed the window
/// taller to fit, the panel's own layout pulled it back, and the deck bounced
/// between 470 and 498 points about fifteen times a second. Sizing the deck to
/// its notes, here, is what stops the content and the window disagreeing.
public struct DeckGeometry: Equatable, Sendable {
    public let panelHeight: Double
    /// Distance from one tab to the next. Equal to the preferred pitch unless
    /// there are more notes than the screen can hold at that spacing.
    public let pitch: Double

    /// - Parameters:
    ///   - chrome: everything in the column that is not a tab (padding, the gap,
    ///     the new-note button).
    ///   - minimumHeight: the deck never gets shorter than this, because the
    ///     editor opens beside it and needs the room.
    ///   - maximumHeight: what the screen can give.
    ///   - minimumPitch: below this a tab's label is no longer a usable target,
    ///     so the deck stops compressing and the overflow is clipped instead.
    public static func fitting(
        noteCount: Int,
        tabHeight: Double,
        preferredPitch: Double,
        minimumPitch: Double,
        chrome: Double,
        minimumHeight: Double,
        maximumHeight: Double
    ) -> DeckGeometry {
        let ceiling = max(maximumHeight, 0)
        let floor = min(minimumHeight, ceiling)
        guard noteCount > 0 else {
            return DeckGeometry(panelHeight: floor, pitch: preferredPitch)
        }
        let needed = chrome + tabHeight + Double(noteCount - 1) * preferredPitch
        if needed <= ceiling {
            return DeckGeometry(panelHeight: max(needed, floor), pitch: preferredPitch)
        }
        // Too many notes for the screen at the usual spacing: shingle them more
        // tightly so every tab stays on screen and reachable.
        let room = ceiling - chrome - tabHeight
        let squeezed = noteCount > 1 ? room / Double(noteCount - 1) : preferredPitch
        return DeckGeometry(panelHeight: ceiling,
                            pitch: min(preferredPitch, max(squeezed, minimumPitch)))
    }
}
