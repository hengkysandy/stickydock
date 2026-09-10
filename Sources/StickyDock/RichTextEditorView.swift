import AppKit
import StickyDockCore
import SwiftUI

/// SwiftUI wrapper around `NoteTextView`.
struct RichTextEditorView: NSViewRepresentable {
    @Binding var rich: RichText
    var textColor: NSColor = .black
    /// Focus is taken when the note is opened deliberately, never when a note
    /// merely appears on screen.
    var focusOnAppear: Bool = false
    var onEscape: () -> Void = {}
    /// Raised while the note has the keyboard, so the view can refuse updates
    /// from underneath the caret.
    var onEditingChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NoteTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.drawsBackground = false
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.baseFont = .systemFont(ofSize: 13)
        textView.font = textView.baseFont
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        // The system find bar. This is all ⌘F needs on the view's side; the menu
        // item that triggers it is in `EditMenu`.
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let coordinator = context.coordinator
        textView.onEscape = { coordinator.parent.onEscape() }
        textView.onFocusChange = { coordinator.parent.onEditingChange($0) }
        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.noteContent = rich

        if focusOnAppear {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NoteTextView else { return }
        // The coordinator outlives this struct, which SwiftUI rebuilds on every
        // render. Without this it keeps writing through the binding captured at
        // the very first render.
        context.coordinator.parent = self
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        // Never rewrite a view the user is typing in. The binding can be a few
        // hundred milliseconds behind the keyboard, and replacing the whole
        // attributed string from a stale value is exactly what made the note
        // blink and swallow characters. While the caret is here, the text view
        // is the authority; anything from elsewhere lands when focus leaves.
        guard !textView.isTyping else { return }
        if textView.noteContent != rich {
            textView.noteContent = rich
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditorView
        weak var textView: NoteTextView?

        init(_ parent: RichTextEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NoteTextView else { return }
            parent.rich = textView.noteContent
        }
    }
}
