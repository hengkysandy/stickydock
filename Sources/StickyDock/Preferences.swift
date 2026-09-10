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

    /// Where the local cache lives. Application Support, not iCloud: it is a
    /// cache, and two Macs writing one SQLite file over iCloud would corrupt it.
    static var databaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("notes.sqlite")
    }
}
