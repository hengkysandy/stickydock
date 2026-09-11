import AppKit
import StickyDockCore

/// Runs the sync on a timer and keeps the UI honest about what happened.
///
/// Apple Notes raises no change notifications, so polling is the only option.
/// The interval follows attention: often while the dock is open and the user is
/// looking at it, rarely while it is a stripe on the edge of the screen.
@MainActor
final class SyncCoordinator {
    private let engine: SyncEngine
    private weak var state: AppState?
    private var timer: Timer?
    private var running = false
    /// Once the user has been told the permission is off, stop nagging until the
    /// next launch.
    private var reportedAuthorisationProblem = false

    private let activeInterval: TimeInterval = 15
    private let idleInterval: TimeInterval = 60

    init(engine: SyncEngine, state: AppState) {
        self.engine = engine
        self.state = state
    }

    func start() {
        scheduleTimer(after: 2)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called after a local edit settles. Debounced by the caller, then given a
    /// couple of seconds so a burst of typing turns into one sync, not ten.
    func syncSoon() {
        scheduleTimer(after: 2)
    }

    func syncNow() {
        runSync()
    }

    /// Called when the pause setting changes, so turning it back on syncs at
    /// once rather than waiting out the current interval.
    func pauseChanged() {
        if Preferences.syncPaused {
            state?.lastSyncSummary = "Syncing paused"
        } else {
            scheduleTimer(after: 0.2)
        }
    }

    private func scheduleTimer(after seconds: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.runSync() }
        }
        // `.common` rather than a plain scheduled timer. The run loop sits in
        // event-tracking mode while a menu is open or the pointer is dragging,
        // and a default-mode timer does not fire at all during that, so syncing
        // would quietly stall for as long as the user kept interacting.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func nextInterval() -> TimeInterval {
        (state?.isExpanded ?? false) ? activeInterval : idleInterval
    }

    private func runSync() {
        guard !running else {
            scheduleTimer(after: nextInterval())
            return
        }
        // Paused means paused. Edits still save locally; only the trip to
        // Apple Notes waits, and it resumes without needing a nudge.
        if Preferences.syncPaused {
            state?.lastSyncSummary = "Syncing paused"
            scheduleTimer(after: nextInterval())
            return
        }
        // Never sync mid-sentence. A sync ends by refreshing the note lists, and
        // doing that while a keystroke is still waiting to be written is what
        // used to make the editor flicker. Waiting a beat costs nothing: the
        // notes are going nowhere.
        if state?.hasPendingEdit == true {
            scheduleTimer(after: 1)
            return
        }
        running = true

        let engine = self.engine
        Task.detached(priority: .utility) {
            let outcome: Result<SyncReport, Error>
            do {
                outcome = .success(try engine.runOnce())
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.finish(outcome)
            }
        }
    }

    private func finish(_ outcome: Result<SyncReport, Error>) {
        running = false
        switch outcome {
        case .success(let report):
            state?.syncProblem = nil
            state?.lastSyncSummary = report.isEmpty
                ? "Up to date \(Self.clock.string(from: Date()))"
                : report.summary
            // Only republish when something actually changed, and never on top
            // of a keystroke that has not been written yet.
            if !report.isEmpty, state?.hasPendingEdit == false {
                state?.reload()
            }

        case .failure(let error):
            if let bridgeError = error as? NotesBridgeError, bridgeError == .notAuthorised {
                state?.syncProblem = "Not allowed to control Notes"
                if !reportedAuthorisationProblem {
                    reportedAuthorisationProblem = true
                    showAuthorisationAlert()
                }
            } else {
                state?.syncProblem = "Sync failed"
                NSLog("StickyDock sync failed: \(error)")
            }
        }
        scheduleTimer(after: nextInterval())
    }

    private func showAuthorisationAlert() {
        let alert = NSAlert()
        alert.messageText = "StickyDock cannot reach Apple Notes"
        alert.informativeText = """
            Your notes are safe, they just are not syncing to your iPhone yet.

            Open System Settings > Privacy & Security > Automation, find \
            StickyDock, and turn on Notes. Then choose Sync Now from the \
            StickyDock menu.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let settings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            if let url = URL(string: settings) { NSWorkspace.shared.open(url) }
        }
    }

    private static var clock: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }
}
