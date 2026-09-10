import AppKit

/// Finding and focusing the text view inside a SwiftUI `TextEditor`.
///
/// SwiftUI's `@FocusState` is not reliable inside these panels. It is set in
/// `onAppear`, which runs before the window has become key, so AppKit discards
/// the request and the first responder stays the window itself. Typing then goes
/// to whichever app the user was in before, which is worse than nothing
/// happening. Both the dock editor and the desktop notes therefore set the first
/// responder directly.
enum TextViewFocus {

    static func firstEditableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable { return textView }
        for subview in view.subviews {
            if let found = firstEditableTextView(in: subview) { return found }
        }
        return nil
    }

    /// Puts the caret in the window's text view, retrying briefly.
    ///
    /// The retry is not superstition: SwiftUI builds its `NSTextView` on a later
    /// run loop pass, so the first look usually finds nothing at all.
    @MainActor
    static func focus(
        in window: NSWindow,
        attemptsLeft: Int = 8,
        while shouldContinue: @escaping () -> Bool = { true }
    ) {
        guard shouldContinue() else { return }
        if let textView = firstEditableTextView(in: window.contentView) {
            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            focus(in: window, attemptsLeft: attemptsLeft - 1, while: shouldContinue)
        }
    }
}
