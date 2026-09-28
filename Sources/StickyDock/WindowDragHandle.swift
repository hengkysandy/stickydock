import AppKit
import SwiftUI

/// A patch of a window that moves the whole window when dragged.
///
/// `isMovableByWindowBackground` is not enough on its own here. It only works
/// where the view under the pointer says `mouseDownCanMoveWindow`, and SwiftUI's
/// hosting view does not say that for its empty areas. The desktop note's top
/// strip looked draggable and did nothing, so a note dropped on the desktop
/// could be resized but never moved again.
///
/// `performDrag(with:)` hands the drag to the window server, the same way a
/// title bar does. It works for a borderless window, snaps to other windows and
/// screen edges like any other macOS window, and ends in an ordinary
/// `windowDidMove`, which is what saves the new position.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class HandleView: NSView {
        /// The app is rarely frontmost, so the first click on a note is also the
        /// one that has to start the drag.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
