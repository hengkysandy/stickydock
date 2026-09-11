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

        let host = FirstMouseHostingView(
            rootView: DockContentView().environmentObject(state)
        )
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

    /// Asks for key status on hover. It is often refused, because the app is not
    /// frontmost, which is why `FirstMouseHostingView` exists.
    private func claimKeyWindow() {
        makeKeyAndOrderFront(nil)
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
        // The screen with the menu bar, not `NSScreen.main`. `NSScreen.main` is
        // whichever screen holds the key window, so with two displays the dock
        // would jump to the other monitor the moment the user clicked over
        // there. A dock pinned to an edge has to stay put.
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let visible = screen.visibleFrame

        // The height never changes. It used to grow with the note count and then
        // jump to the full panel height on expand, which also slid the panel
        // vertically because it stays centred. Widening, growing and sliding at
        // once is what made opening the deck feel clumsy. Only the width moves.
        let height = min(Theme.panelHeight, visible.height - 40)
        let width: CGFloat
        if !state.isExpanded {
            width = Theme.collapsedWidth
        } else {
            // The deck is only as wide as it needs to be: tabs alone, tabs plus
            // a peek while the pointer rests on one, tabs plus the editor when a
            // note is actually open.
            if state.selectedNoteId != nil {
                width = Theme.tabWidth + Theme.editorWidth + 16
            } else if state.hoveredNote != nil {
                width = Theme.tabWidth + Theme.peekWidth + 16
            } else {
                width = Theme.tabWidth + 10
            }
        }

        let frame = NSRect(
            x: visible.maxX - width - 2,
            y: visible.midY - height / 2,
            width: width,
            height: height
        )
        guard frame != self.frame else { return }
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
        claimKeyWindow()
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
            if self.state.selectedNoteId != nil {
                // Never collapse out from under someone who is typing. But if
                // they have gone off to another app, an open editor left sitting
                // 400pt wide over their work is not "still editing", it is in
                // the way.
                guard !NSApp.isActive else { return }
                self.state.selectedNoteId = nil
            }
            // Clear the hover too, or the next time the deck opens it opens
            // straight into a peek for whichever tab the pointer left last.
            self.state.hoveredNoteId = nil
            self.state.isExpanded = false
            self.layoutForCurrentState()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func focusEditor() {
        TextViewFocus.focus(in: self) { [weak self] in self?.state.selectedNoteId != nil }
    }

    /// Hides or shows the edge dock. The menu bar item is untouched, so there is
    /// always a way to bring it back.
    func setHidden(_ hidden: Bool) {
        if hidden {
            state.selectedNoteId = nil
            state.clearHoverImmediately()
            state.isExpanded = false
            orderOut(nil)
        } else {
            layoutForCurrentState(animated: false)
            orderFront(nil)
        }
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
            // Deliberately no `resignKey()`. That is a method AppKit calls, not
            // one to call yourself: it left the panel believing it was still the
            // key window when it was not, so the next `makeKeyAndOrderFront` was
            // treated as a no-op and the panel silently stopped receiving mouse
            // events. The symptom was every other click on a tab doing nothing.
            NSApp.deactivate()
        }
    }
}
