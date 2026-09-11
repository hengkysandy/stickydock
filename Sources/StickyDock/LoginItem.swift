import ServiceManagement

/// Open at Login, through `SMAppService`.
///
/// The system holds this setting, not `UserDefaults`, which matters: the user can
/// turn it off in System Settings, General, Login Items, and the menu has to show
/// that rather than its own stale copy. So `isEnabled` always asks the system.
///
/// `SMAppService.mainApp` needs no helper bundle and no login-item plist. It does
/// need the app to be somewhere the system is willing to launch from, which in
/// practice means Applications rather than a build folder.
@MainActor
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the system has the setting but the user has switched it off
    /// themselves, which is not the same as never having asked for it.
    static var deniedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Returns nil on success, or a sentence worth showing the user.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            // The usual cause is running from a build folder rather than
            // Applications. Say that, because the raw error does not.
            return """
                macOS would not \(enabled ? "add" : "remove") StickyDock \
                as a login item.

                This usually means the app is not in your Applications folder. \
                Move it there and try again.

                (\(error.localizedDescription))
                """
        }
    }
}
