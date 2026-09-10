import AppKit
import SwiftUI

/// A hosting view that acts on the first click, rather than swallowing it.
///
/// The dock is deliberately never the frontmost app, and a window in an app that
/// is not frontmost cannot be the key window. AppKit gives the panel key status
/// as a *result* of a click, which means the click that caused it is spent doing
/// that and never reaches the content. The symptom was every other click on a
/// tab doing nothing: the first click promoted the window, the second worked.
///
/// `acceptsFirstMouse` is the answer to exactly this: deliver the click anyway.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
