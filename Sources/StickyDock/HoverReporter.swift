import AppKit
import SwiftUI

/// Reports when the pointer enters and leaves a SwiftUI view.
///
/// SwiftUI's own `.onHover` is not usable here. It installs a tracking area that
/// only fires while the app is active, and this panel is deliberately never
/// active: reaching for your notes must not pull you out of what you were doing.
/// An `.activeAlways` tracking area reports regardless.
///
/// It never takes a click. `hitTest` returns nil, so the drag gesture on the tab
/// above it still sees every mouse event.
struct HoverReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackingView)?.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}
