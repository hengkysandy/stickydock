import Foundation

/// Working out where a dragged tab belongs, and writing that order down.
///
/// Kept here rather than in the view so the arithmetic can be tested. The three
/// worst bugs this app has had all lived in view-layer state that nothing could
/// exercise.
public enum NoteOrder {

    /// Which slot a vertical drag has reached.
    ///
    /// `pitch` is the distance from one tab to the next, which is the tab height
    /// less the amount they overlap. Half a pitch of travel is enough to claim
    /// the next slot, so the tab swaps as its midpoint crosses its neighbour's
    /// rather than only once it has cleared it completely.
    public static func targetIndex(
        movingFrom origin: Int, byVerticalDrag drag: Double, pitch: Double, count: Int
    ) -> Int {
        guard count > 0, pitch > 0 else { return origin }
        let moved = (drag / pitch).rounded()
        return min(max(origin + Int(moved), 0), count - 1)
    }

    /// The list as it should look while a note is being dragged to a new slot.
    ///
    /// Returns the input untouched when nothing would move, so a redraw is not
    /// triggered for a drag that has not yet crossed anything.
    public static func moving(_ noteId: String, to target: Int, in notes: [Note]) -> [Note] {
        guard let from = notes.firstIndex(where: { $0.id == noteId }) else { return notes }
        let to = min(max(target, 0), notes.count - 1)
        guard from != to else { return notes }
        var reordered = notes
        let note = reordered.remove(at: from)
        reordered.insert(note, at: to)
        return reordered
    }

    /// How far the carried tab is drawn from its resting place.
    ///
    /// Clamped to the ends of the deck, so flinging the pointer off the bottom
    /// of the screen does not drag the tab out of the panel with it.
    public static func carriedOffset(
        drag: Double, origin: Int, pitch: Double, count: Int
    ) -> Double {
        guard count > 0 else { return 0 }
        return min(max(drag, -Double(origin) * pitch), Double(count - 1 - origin) * pitch)
    }

    /// How far a tab steps aside to open a gap at `target`.
    ///
    /// The list itself is **not** reordered while the drag is running. Moving a
    /// row of a SwiftUI list moves the very view whose gesture is driving the
    /// drag, and the gesture ends there and then, halfway through. That showed
    /// up as a drag committing itself three or four times on the way down. So
    /// the order stays fixed for the length of the drag and the tabs move by an
    /// offset instead; only the release writes anything.
    public static func displacement(
        atIndex index: Int, origin: Int, target: Int, pitch: Double
    ) -> Double {
        guard index != origin else { return 0 }
        if origin < target, index > origin, index <= target { return -pitch }
        if origin > target, index >= target, index < origin { return pitch }
        return 0
    }

    /// Numbers a displayed order 0, 1, 2 and returns **only the notes that
    /// actually moved**.
    ///
    /// Only the movers are returned because each one written back bumps its
    /// `updatedAt`, which is what tells the other Mac the order changed. Writing
    /// every note would claim they had all just been touched.
    public static func reindexed(_ notes: [Note], now: Date = Date()) -> [Note] {
        notes.enumerated().compactMap { index, note in
            guard note.sortIndex != index else { return nil }
            var moved = note
            moved.sortIndex = index
            moved.updatedAt = now
            return moved
        }
    }
}
