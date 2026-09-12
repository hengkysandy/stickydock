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
    private var dragTimer: Timer?
    /// Held here rather than captured by the timer's closure. Swift 6 will not
    /// let a non-isolated timer block carry a main-actor closure across the
    /// boundary, and there is no need for it to.
    private var dragCompletion: (@MainActor () -> Void)?
    private var dragStartedAt = Date()
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

    /// Starts a drag and returns immediately. `onDrop` runs when the mouse
    /// comes up.
    ///
    /// A timer rather than a nested `NSApp.nextEvent` tracking loop, and that
    /// distinction is the whole reason this reads the way it does. The nested
    /// loop worked, but it only ever dequeued mouse events, so nothing else in
    /// the app got to run: the note being dragged rendered as a bare coloured
    /// rectangle with no text in it until the moment it was dropped.
    ///
    /// It also cannot rely on SwiftUI's `onEnded`, which is never called once
    /// the note's own window is under the pointer, so the release is detected by
    /// asking the system whether the button is still held. That needs no
    /// permission and cannot be swallowed by anything.
    ///
    /// The timer is added to `.common` modes on purpose. A plain scheduled timer
    /// runs only in the default mode, and the run loop is in event-tracking mode
    /// for the entire duration of a mouse drag, so it would never once fire.
    func beginDrag(noteId: String, onDrop: @escaping @MainActor () -> Void) {
        guard let window = show(noteId: noteId) else { onDrop(); return }
        window.isBeingDragged = true
        // The window lands directly under the pointer, and a window under the
        // pointer swallows the mouse events. Transparent for the length of the
        // drag, solid again the moment it is dropped.
        window.ignoresMouseEvents = true
        draggingWindow = window
        moveDrag(to: pointerLocation())

        dragTimer?.invalidate()
        dragCompletion = onDrop
        dragStartedAt = Date()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickDrag() }
        }
        dragTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tickDrag() {
        let stillHeld = NSEvent.pressedMouseButtons & 1 != 0
        // The 60s cap is a backstop: a mouse-up that never arrives must not
        // leave a note stuck to the pointer for ever.
        if stillHeld, Date().timeIntervalSince(dragStartedAt) < 60 {
            moveDrag(to: pointerLocation())
            return
        }
        dragTimer?.invalidate()
        dragTimer = nil
        endDrag()
        let finish = dragCompletion
        dragCompletion = nil
        finish?()
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
        dragTimer?.invalidate()
        dragTimer = nil
        // Array(), because `close` removes from `windows` and mutating a
        // dictionary while iterating its own keys view is undefined behaviour.
        for id in Array(windows.keys) { close(noteId: id) }
    }

    /// Surfaces every desktop note above whatever is covering it.
    ///
    /// `orderFront` alone is not enough once notes sit at normal window level:
    /// it only reorders them within this app, and this app is almost never the
    /// active one, so a note buried under the window you are working in stayed
    /// buried. Since notes no longer float, this menu item is the only way back
    /// to a covered note, so it has to actually work.
    func bringAllToFront() {
        NSApp.activate(ignoringOtherApps: true)
        for window in windows.values { window.orderFrontRegardless() }
    }

    func isOpen(noteId: String) -> Bool { windows[noteId] != nil }

    /// Applies the on-top setting to notes that are already on screen, so the
    /// menu item takes effect without reopening anything.
    func applyStackingLevel() {
        for window in windows.values { window.applyStackingLevel() }
    }

    /// Brings one desktop note forward and gives it focus.
    func focus(noteId: String) {
        guard let window = show(noteId: noteId) else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
