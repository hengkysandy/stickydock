import AppKit
import StickyDockCore

/// Owns every note window on the desktop.
///
/// One place holds the windows so that "is this note already open" has exactly
/// one answer, and so a note archived or deleted from anywhere in the app cannot
/// leave an orphan window behind.
@MainActor
final class StickyWindowManager {
    private var windows: [String: StickyNoteWindow] = [:]
    /// The window currently being pulled out of the deck.
    ///
    /// It lives here, not in the card view's `@State`. The card re-renders the
    /// instant the drag begins, and view-local state does not reliably survive
    /// that, so the window would be created and then stop following the pointer.
    private var draggingWindow: StickyNoteWindow?
    private unowned let state: AppState

    init(state: AppState) {
        self.state = state
    }

    /// Reopens whatever was on the desktop when the app last quit.
    func restoreAll() {
        for note in state.detachedNotes {
            show(noteId: note.id)
        }
    }

    @discardableResult
    func show(noteId: String) -> StickyNoteWindow? {
        if let existing = windows[noteId] {
            existing.orderFront(nil)
            return existing
        }
        // Read through the store rather than a published list: during a drag the
        // lists are deliberately stale, and this must still work.
        guard let note = try? state.store.find(id: noteId) else { return nil }

        let saved = note.frame ?? DetachedFrame.defaultFrame(
            around: NotePoint(x: Double(NSEvent.mouseLocation.x),
                              y: Double(NSEvent.mouseLocation.y))
        )
        let safe = DetachedFrame.clamp(saved, toAnyOf: Self.currentScreens())
        let window = StickyNoteWindow(
            noteId: noteId, state: state,
            frame: NSRect(x: safe.x, y: safe.y, width: safe.width, height: safe.height)
        )
        windows[noteId] = window
        window.orderFront(nil)
        // A clamp that actually moved the window must be written back, or the
        // note keeps being restored to a screen that is not there.
        if safe != saved { state.setFrame(safe, for: noteId) }
        return window
    }

    // MARK: - Dragging a note out of the deck

    /// Runs the whole drag, from the moment the note leaves the deck to the
    /// moment the mouse comes up, and returns only when it is over.
    ///
    /// This is a nested AppKit event-tracking loop rather than a continuation of
    /// the SwiftUI gesture, and that is not a stylistic choice. SwiftUI delivers
    /// `onChanged` faithfully all the way across the screen and then never calls
    /// `onEnded` at all once the note's own window is following the pointer, so
    /// the drop position was never recorded and the note stayed pinned where it
    /// was born. Pulling the events straight off the queue removes every part of
    /// that problem: nothing can cancel this loop except the mouse coming up.
    ///
    /// `onDrop` runs after the last event, on the main thread, before returning.
    func runDrag(noteId: String, onDrop: () -> Void) {
        guard let window = show(noteId: noteId) else { return }
        window.isBeingDragged = true
        // The window lands directly under the pointer, and a window under the
        // pointer swallows the mouse events. Transparent for the length of the
        // drag, solid again the moment it is dropped.
        window.ignoresMouseEvents = true
        draggingWindow = window
        moveDrag(to: pointerLocation())

        // A backstop, so a lost mouse-up can never leave the app stuck in here.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            guard let event = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date().addingTimeInterval(0.5),
                inMode: .eventTracking,
                dequeue: true
            ) else {
                // No event for half a second. If the button is no longer held,
                // the mouse-up happened somewhere we could not see it.
                if NSEvent.pressedMouseButtons & 1 == 0 { break }
                continue
            }
            if event.type == .leftMouseUp { break }
            moveDrag(to: pointerLocation())
        }

        endDrag()
        onDrop()
    }

    func moveDrag(to point: NotePoint) {
        guard let window = draggingWindow else { return }
        window.setFrameOrigin(NSPoint(
            x: point.x - window.frame.width / 2,
            y: point.y - window.frame.height / 2
        ))
    }

    private func endDrag() {
        guard let window = draggingWindow else { return }
        window.ignoresMouseEvents = false
        window.isBeingDragged = false
        window.saveFrame()
        window.orderFront(nil)
        draggingWindow = nil
    }

    private func pointerLocation() -> NotePoint {
        let mouse = NSEvent.mouseLocation
        return NotePoint(x: Double(mouse.x), y: Double(mouse.y))
    }

    func close(noteId: String) {
        if draggingWindow?.noteId == noteId { draggingWindow = nil }
        guard let window = windows.removeValue(forKey: noteId) else { return }
        window.orderOut(nil)
        window.close()
    }

    func closeAll() {
        for id in windows.keys { close(noteId: id) }
    }

    func bringAllToFront() {
        for window in windows.values { window.orderFront(nil) }
    }

    var openCount: Int { windows.count }

    /// Screens as plain rectangles, so the geometry itself stays testable.
    static func currentScreens() -> [NoteFrame] {
        NSScreen.screens.map { screen in
            NoteFrame(
                x: screen.visibleFrame.origin.x, y: screen.visibleFrame.origin.y,
                width: screen.visibleFrame.width, height: screen.visibleFrame.height
            )
        }
    }
}
