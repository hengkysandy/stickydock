import AppKit
import SwiftUI
import StickyDockCore

/// Click it, press a combination, and it becomes that shortcut.
///
/// A plain `NSView` rather than anything SwiftUI offers, because capturing a raw
/// key press with its modifiers, before the system turns it into text, needs
/// `keyDown` and `performKeyEquivalent`. The latter matters: without it, a
/// combination that matches a menu item elsewhere would be eaten before this
/// view ever saw it.
struct ShortcutRecorder: NSViewRepresentable {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = onChange
        view.combo = combo
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onChange = onChange
        view.combo = combo
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var onChange: ((KeyCombo?) -> Void)?
        var combo: KeyCombo?
        private var recording = false {
            didSet { needsDisplay = true }
        }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 132, height: 24) }

        override func mouseDown(with event: NSEvent) {
            recording = true
            window?.makeFirstResponder(self)
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return true
        }

        /// Claims the combination before the menu system can act on it.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return false }
            return handle(event)
        }

        override func keyDown(with event: NSEvent) {
            guard recording, handle(event) else {
                super.keyDown(with: event)
                return
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            // Escape abandons, Delete clears. Neither is a shortcut worth binding.
            if event.keyCode == 53 {
                recording = false
                window?.makeFirstResponder(nil)
                return true
            }
            if event.keyCode == 51 {
                onChange?(nil)
                recording = false
                window?.makeFirstResponder(nil)
                return true
            }

            var mods: UInt32 = 0
            if event.modifierFlags.contains(.control) { mods |= KeyCombo.control }
            if event.modifierFlags.contains(.option)  { mods |= KeyCombo.option }
            if event.modifierFlags.contains(.shift)   { mods |= KeyCombo.shift }
            if event.modifierFlags.contains(.command) { mods |= KeyCombo.command }

            let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            // A bare key would fire while typing anywhere on the machine.
            guard candidate.hasModifier else { NSSound.beep(); return true }

            onChange?(candidate)
            recording = false
            window?.makeFirstResponder(nil)
            return true
        }

        override func draw(_ dirtyRect: NSRect) {
            let rounded = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                       xRadius: 5, yRadius: 5)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.16)
                       : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
            rounded.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            rounded.lineWidth = recording ? 2 : 1
            rounded.stroke()

            let text = recording ? "Press keys…" : (combo?.display ?? "Not set")
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let colour: NSColor = recording ? .controlAccentColor
                                            : (combo == nil ? .tertiaryLabelColor : .labelColor)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: combo == nil ? .regular : .medium),
                .foregroundColor: colour,
                .paragraphStyle: style,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                in: NSRect(x: 0, y: (bounds.height - size.height) / 2,
                           width: bounds.width, height: size.height),
                withAttributes: attributes
            )
        }
    }
}
