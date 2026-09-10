import AppKit
import SwiftUI
import StickyDockCore

/// One note, in its own window on the desktop.
///
/// Level is `.floating`, unlike Apple's Stickies, which sit at normal level and
/// get buried. That is a deliberate difference: the dock already covers the
/// "keep it out of my way" case, so dragging a note out is an explicit request
/// to keep it in front. One click puts it back.
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

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        minSize = NSSize(
            width: DetachedFrame.minimumSize.width,
            height: DetachedFrame.minimumSize.height
        )

        let host = NSHostingView(
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
        MainActor.assumeIsolated { saveFrame() }
    }
}
