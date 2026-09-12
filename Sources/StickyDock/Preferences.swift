import Foundation
import StickyDockCore

/// User settings, in `UserDefaults`. Small enough that a settings window can
/// wait; the defaults are right for almost everyone.
struct Preferences {
    /// UserDefaults is thread-safe but not Sendable, so it is fetched per call
    /// rather than held in a static.
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let account = "notesAccount"
        static let folder = "notesFolder"
        static let pollSeconds = "pollSeconds"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let syncPaused = "syncPaused"
        static let dockHidden = "dockHidden"
        static let notesOnTop = "notesOnTop"
    }

    /// The Notes account to mirror into. iCloud is the one that reaches the phone.
    static var account: String {
        get { defaults.string(forKey: Key.account) ?? "iCloud" }
        set { defaults.set(newValue, forKey: Key.account) }
    }

    /// A dedicated folder, never the top level, so StickyDock can never touch a
    /// note the user did not put there.
    static var folder: String {
        get { defaults.string(forKey: Key.folder) ?? "StickyDock" }
        set { defaults.set(newValue, forKey: Key.folder) }
    }

    static var hotKeyEnabled: Bool {
        get { defaults.object(forKey: Key.hotKeyEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hotKeyEnabled) }
    }

    /// Syncing held off until the user turns it back on. Edits keep saving
    /// locally the whole time; only the trip to Apple Notes waits.
    static var syncPaused: Bool {
        get { defaults.bool(forKey: Key.syncPaused) }
        set { defaults.set(newValue, forKey: Key.syncPaused) }
    }

    /// The edge stripe hidden from view. The menu bar item stays, so there is
    /// always a way back.
    static var dockHidden: Bool {
        get { defaults.bool(forKey: Key.dockHidden) }
        set { defaults.set(newValue, forKey: Key.dockHidden) }
    }

    /// Whether desktop notes sit above every other window.
    ///
    /// Off by default. It was on originally, on the reasoning that dragging a
    /// note out meant "keep this in front", and that turned out to be wrong:
    /// a note pinned over the window you are working in is not a note you are
    /// reading, it is one you are trying to see past.
    static var notesOnTop: Bool {
        get { defaults.bool(forKey: Key.notesOnTop) }
        set { defaults.set(newValue, forKey: Key.notesOnTop) }
    }

    // MARK: - Shortcuts

    /// The shortcut bound to an action, or nil for none.
    ///
    /// "Never set" and "deliberately cleared" are different states, so a cleared
    /// shortcut is stored as an explicit empty marker rather than by removing
    /// the key. Otherwise clearing New Note would silently hand back its factory
    /// default on the next launch.
    static func shortcut(for action: ShortcutAction) -> KeyCombo? {
        let key = "shortcut.\(action.rawValue)"
        guard let raw = defaults.string(forKey: key) else { return action.factoryDefault }
        guard raw != "none", let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    static func setShortcut(_ combo: KeyCombo?, for action: ShortcutAction) {
        let key = "shortcut.\(action.rawValue)"
        guard let combo, let data = try? JSONEncoder().encode(combo) else {
            defaults.set("none", forKey: key)
            return
        }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: key)
    }

    static func resetShortcut(for action: ShortcutAction) {
        defaults.removeObject(forKey: "shortcut.\(action.rawValue)")
    }

    /// Where the local cache lives. Application Support, not iCloud: it is a
    /// cache, and two Macs writing one SQLite file over iCloud would corrupt it.
    static var databaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("notes.sqlite")
    }
}
