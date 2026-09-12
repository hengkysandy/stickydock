import AppKit
import StickyDockCore

/// Registers every configured shortcut, and re-registers the lot whenever one
/// changes.
///
/// Re-registering everything rather than the one that changed keeps this honest:
/// there is one code path, and it is the one that runs at launch, so a shortcut
/// edited at runtime behaves exactly like one loaded from settings.
@MainActor
final class HotKeyCenter {
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    private let perform: (ShortcutAction) -> Void
    /// Actions whose shortcut could not be claimed, usually because something
    /// else on the machine already owns that combination.
    private(set) var refused: Set<ShortcutAction> = []

    init(perform: @escaping (ShortcutAction) -> Void) {
        self.perform = perform
    }

    func reload() {
        for hotKey in hotKeys.values { hotKey.unregister() }
        hotKeys.removeAll()
        refused.removeAll()

        for action in ShortcutAction.allCases {
            // New Note has its own on/off switch, kept from before shortcuts
            // were configurable.
            if action == .newNote, !Preferences.hotKeyEnabled { continue }
            guard let combo = Preferences.shortcut(for: action), combo.hasModifier else { continue }
            if let hotKey = HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers,
                                   action: { [weak self] in self?.perform(action) }) {
                hotKeys[action] = hotKey
            } else {
                refused.insert(action)
                NSLog("StickyDock: could not claim \(combo.display) for \(action.title).")
            }
        }
    }

    func stop() {
        for hotKey in hotKeys.values { hotKey.unregister() }
        hotKeys.removeAll()
    }
}
