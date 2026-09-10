import AppKit
import SwiftUI
import StickyDockCore

/// Holds the single All Notes window, so choosing the menu item twice brings the
/// existing window forward instead of opening a second one.
@MainActor
final class AllNotesWindow {
    private var window: NSWindow?
    private let state: AppState
    private let onOpen: (Note) -> Void

    init(state: AppState, onOpen: @escaping (Note) -> Void) {
        self.state = state
        self.onOpen = onOpen
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        created.title = "All Notes"
        created.isReleasedWhenClosed = false
        created.center()
        created.contentView = NSHostingView(
            rootView: AllNotesView(onOpen: onOpen).environmentObject(state)
        )
        window = created

        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}
