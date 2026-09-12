import AppKit
import SwiftUI
import StickyDockCore

/// One note, in its own window on the desktop.
///
/// Sits at normal window level by default, so it goes behind whatever you are
/// working in, the way Apple's Stickies do.
///
/// It used to float above everything, on the reasoning that dragging a note out
/// of the dock meant "keep this in front". That was wrong in practice: a note
/// pinned over the window you are typing in is not a note you are reading, it is
/// one you are trying to see past. Turn it back on per taste with
/// Settings, Keep Desktop Notes on Top.
@MainActor
final class StickyNoteWindow: NSPanel {
    let noteId: String
    private let state: AppState
    /// Set while the note is being dragged out of the deck, so the frame the user
    /// is still moving is not written to the database on every mouse event.
    var isBeingDragged = false

    init(noteId: String, state: AppState, frame: NSRect) {
        self.noteId = noteId
        self.state = state
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        applyStackingLevel()
        minSize = NSSize(
            width: DetachedFrame.minimumSize.width,
            height: DetachedFrame.minimumSize.height
        )

        // Same reason as the dock: this app is rarely frontmost, and without
        // this the first click on a desktop note is spent making the window key
        // instead of placing the caret.
        let host = FirstMouseHostingView(
            rootView: StickyNoteView(noteId: noteId).environmentObject(state)
        )
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.wantsLayer = true
        host.layer?.cornerRadius = 8
        host.layer?.masksToBounds = true
        contentView = host
        delegate = self
    }

    /// Above everything, or in the ordinary pile with every other window.
    ///
    /// `isFloatingPanel` has to move with the level. Left at true, an NSPanel
    /// keeps floating no matter what `level` says.
    func applyStackingLevel() {
        let onTop = Preferences.notesOnTop
        isFloatingPanel = onTop
        level = onTop ? .floating : .normal
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Focus goes to the text when the user clicks the note, never before, so a
    /// note appearing on the desktop cannot steal what someone is typing.
    ///
    /// The activation is deferred to the next run loop pass on purpose. Making a
    /// window key in the middle of dispatching a mouse-down swallows that event:
    /// the click never reaches the text view, and typing goes to whatever app
    /// was in front. Let the event finish first, then take focus.
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        guard event.type == .leftMouseDown, !isBeingDragged else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            if !isKeyWindow { makeKeyAndOrderFront(nil) }
            TextViewFocus.focus(in: self)
        }
    }

    func saveFrame() {
        guard !isBeingDragged else { return }
        state.setFrame(
            NoteFrame(x: frame.origin.x, y: frame.origin.y,
                      width: frame.width, height: frame.height),
            for: noteId
        )
    }
}

extension StickyNoteWindow: NSWindowDelegate {
    nonisolated func windowDidMove(_ notification: Notification) {
        MainActor.assumeIsolated { saveFrame() }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        MainActor.assumeIsolated {
            saveFrame()
            // This window is transparent with a rounded corner mask, so macOS
            // builds its shadow from the alpha mask and caches it. Resizing
            // changes that shape, and a cached shadow from the old size draws as
            // a hard outline that no longer fits the note.
            invalidateShadow()
        }
    }
}
