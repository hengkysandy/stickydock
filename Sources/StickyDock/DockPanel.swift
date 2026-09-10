import AppKit
import SwiftUI
import StickyDockCore

/// A view that reports when the pointer crosses into or out of it.
///
/// This is why hover works without any Accessibility permission. A global mouse
/// monitor would need one, and a sticky-note app has no business asking for the
/// right to watch every event on the machine. A tracking area inside our own
/// window needs nothing at all.
final class HoverReportingView: NSView {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            // .activeAlways matters: the panel must react even when StickyDock
            // is not the active app, which is nearly always.
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// The floating panel docked to the edge of the screen.
@MainActor
final class DockPanel: NSPanel {
    private let state: AppState
    private var collapseWork: DispatchWorkItem?

    init(state: AppState) {
        self.state = state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.collapsedWidth, height: 200),
            // .nonactivatingPanel is the key style: clicking a note must not
            // steal focus from whatever the user is actually working in.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Follow the user across Spaces and sit over full-screen apps, because a
        // note pinned to one desktop is a note you forget about.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none

        let host = NSHostingView(rootView: DockContentView().environmentObject(state))
        host.translatesAutoresizingMaskIntoConstraints = false

        let container = HoverReportingView()
        container.onEnter = { [weak self] in self?.expand() }
        container.onExit = { [weak self] in self?.scheduleCollapse() }
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Take focus on a click, never on a hover.
    ///
    /// macOS only delivers a continuous mouse-drag stream to the **active**
    /// application. A background app gets the mouse-down and the mouse-up and
    /// nothing in between, which is exactly enough for a button and not nearly
    /// enough to drag a note out of the deck. Hovering still takes nothing, so
    /// glancing at your notes never pulls you out of what you were doing.
    // MARK: - Geometry

    /// Re-anchors the panel to the right edge at whatever size the current state
    /// calls for.
    func layoutForCurrentState(animated: Bool = true) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame

        let width: CGFloat
        let height: CGFloat
        if !state.isExpanded {
            width = Theme.collapsedWidth
            // Grow with the number of notes, but never past two thirds of the screen.
            let wanted = CGFloat(max(state.notes.count, 1)) * 19 + 20
            height = min(max(wanted, 60), visible.height * 0.66)
        } else {
            width = state.selectedNoteId == nil ? Theme.expandedWidth : Theme.editorWidth
            height = min(Theme.panelHeight, visible.height - 40)
        }

        let frame = NSRect(
            x: visible.maxX - width - 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
    }

    // MARK: - Hover

    func expand() {
        collapseWork?.cancel()
        collapseWork = nil
        guard !state.isExpanded else { return }
        state.isExpanded = true
        layoutForCurrentState()
        // Become key on hover, but never activate the app. SwiftUI will not run a
        // drag gesture in a window that is not key, so without this a note cannot
        // be dragged out of the deck at all. Doing it here rather than on
        // mouse-down matters: making a window key in the middle of dispatching a
        // mouse-down swallows that event, the gesture never starts, and every
        // drag that follows is ignored. A key panel in an inactive app still
        // receives no keystrokes, so nothing is stolen from the app in front.
        makeKeyAndOrderFront(nil)
    }

    /// A short grace period, so nudging the pointer a few pixels past the edge
    /// of the panel does not slam it shut mid-read.
    func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Never collapse out from under someone who is typing.
            guard self.state.selectedNoteId == nil else { return }
            self.state.isExpanded = false
            self.layoutForCurrentState()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func focusEditor() {
        TextViewFocus.focus(in: self) { [weak self] in self?.state.selectedNoteId != nil }
    }

    func openEditor(for noteId: String) {
        state.selectedNoteId = noteId
        expand()
        selectionChanged(to: noteId)
    }

    /// Focus follows intent: browsing the deck never steals it, editing takes it.
    ///
    /// This panel is `.nonactivatingPanel`, which is right for the dormant stripe
    /// and the fanned deck: glancing at a note should not pull you out of
    /// whatever you were working in. The cost is that clicking the panel does not
    /// make it key, so a text editor inside it receives no keystrokes at all.
    /// Opening a note therefore activates the app explicitly, and closing it
    /// hands focus straight back.
    func selectionChanged(to noteId: String?) {
        layoutForCurrentState()
        if noteId != nil {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            focusEditor()
        } else if isKeyWindow {
            resignKey()
            NSApp.deactivate()
        }
    }
}
