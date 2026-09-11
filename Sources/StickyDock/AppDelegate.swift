import AppKit
import Carbon.HIToolbox
import Combine
import StickyDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var state: AppState?
    private var panel: DockPanel?
    private var coordinator: SyncCoordinator?
    private var allNotes: AllNotesWindow?
    private var stickyWindows: StickyWindowManager?
    private var hotKey: HotKey?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: NoteStore
        do {
            store = try NoteStore(path: Preferences.databaseURL.path)
        } catch {
            fatalCannotOpenDatabase(error)
            return
        }

        let state = AppState(store: store)
        self.state = state

        let panel = DockPanel(state: state)
        self.panel = panel
        panel.layoutForCurrentState(animated: false)
        if Preferences.dockHidden {
            panel.setHidden(true)
        } else {
            panel.orderFront(nil)
        }

        // The stripe's height follows the note count, so any change to the list
        // has to re-anchor the panel.
        state.$notes
            .receive(on: RunLoop.main)
            .sink { [weak panel] _ in panel?.layoutForCurrentState() }
            .store(in: &cancellables)
        // Opening a note has to take keyboard focus, or the editor gets no
        // keystrokes. Closing it has to give focus back.
        state.$selectedNoteId
            .receive(on: RunLoop.main)
            .sink { [weak panel] noteId in panel?.selectionChanged(to: noteId) }
            .store(in: &cancellables)
        // The panel widens to make room for the peek, so hovering a tab has to
        // re-anchor it just like selecting one does.
        state.$hoveredNoteId
            .receive(on: RunLoop.main)
            .sink { [weak panel] _ in panel?.layoutForCurrentState() }
            .store(in: &cancellables)

        // Desktop windows come back before the first sync, so notes that were on
        // screen at quit are on screen at launch.
        let windows = StickyWindowManager(state: state)
        state.windows = windows
        stickyWindows = windows
        windows.restoreAll()

        EditMenu.install()
        setUpSync(state: state, store: store)
        setUpStatusItem()
        setUpHotKey()

        allNotes = AllNotesWindow(state: state) { [weak self] note in
            // A note that is out on the desktop is not in the dock's list, so
            // opening it in the dock editor would show an empty panel. Bring its
            // own window forward instead.
            if note.isDetached {
                self?.stickyWindows?.focus(noteId: note.id)
            } else {
                self?.panel?.openEditor(for: note.id)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The editor debounces writes by 400ms. Quitting mid-sentence must not
        // drop the last thing typed.
        state?.flushPendingEdit()
        coordinator?.stop()
        hotKey?.unregister()
        stickyWindows?.closeAll()
    }

    // MARK: - Wiring

    private func setUpSync(state: AppState, store: NoteStore) {
        let bridge: NotesBridge
        do {
            bridge = try NotesBridge.bundled()
        } catch {
            state.syncProblem = "Bridge script missing"
            NSLog("StickyDock: \(error)")
            return
        }

        // No iCloud Drive means local-only colours, never a broken app.
        let sidecarDirectory = SidecarStore.iCloudDirectory()
            ?? Preferences.databaseURL.deletingLastPathComponent()
        let sidecar = SidecarStore(directory: sidecarDirectory)
        if SidecarStore.iCloudDirectory() == nil {
            NSLog("StickyDock: iCloud Drive not available, colours stay on this Mac.")
        }

        let engine = SyncEngine(
            store: store, bridge: bridge, sidecar: sidecar,
            account: Preferences.account, folder: Preferences.folder
        )
        let coordinator = SyncCoordinator(engine: engine, state: state)
        self.coordinator = coordinator
        state.onLocalEdit = { [weak coordinator] in coordinator?.syncSoon() }
        coordinator.start()
    }

    private func setUpHotKey() {
        guard Preferences.hotKeyEnabled else { return }
        // Control + Option + N. Carbon, so no Accessibility permission is needed.
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_N),
            modifiers: UInt32(controlKey | optionKey)
        ) { [weak self] in
            self?.newNote()
        }
        if hotKey == nil {
            NSLog("StickyDock: could not register ⌃⌥N, something else has it.")
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "note.text", accessibilityDescription: "StickyDock"
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let new = NSMenuItem(title: "New Note", action: #selector(newNote), keyEquivalent: "n")
        new.keyEquivalentModifierMask = [.control, .option]
        new.target = self
        menu.addItem(new)

        let all = NSMenuItem(title: "All Notes…", action: #selector(showAllNotes), keyEquivalent: "")
        all.target = self
        menu.addItem(all)

        // Desktop notes are floating windows with no Dock icon behind them, so
        // there has to be a way to find one that ended up under something.
        let front = NSMenuItem(
            title: "Bring Desktop Notes to Front",
            action: #selector(bringDesktopNotesToFront), keyEquivalent: ""
        )
        front.target = self
        front.tag = Self.desktopNotesTag
        menu.addItem(front)

        menu.addItem(.separator())

        let sync = NSMenuItem(title: "Sync Now", action: #selector(syncNow), keyEquivalent: "")
        sync.target = self
        menu.addItem(sync)

        let status = NSMenuItem(title: "Not synced yet", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = Self.statusLineTag
        menu.addItem(status)

        let folder = NSMenuItem(
            title: "Notes folder: \(Preferences.account) › \(Preferences.folder)",
            action: nil, keyEquivalent: ""
        )
        folder.isEnabled = false
        menu.addItem(folder)

        menu.addItem(.separator())
        menu.addItem(settingsItem())
        menu.addItem(aboutItem())
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit StickyDock",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        menu.addItem(quit)
        return menu
    }

    private static let statusLineTag = 991
    private static let desktopNotesTag = 992
    private enum Toggle: Int {
        case openAtLogin = 801, hotKey = 802, pauseSync = 803, hideDock = 804
    }

    /// Settings live in a submenu rather than at the top level, so the things
    /// used every day stay one click away.
    private func settingsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Settings")

        let entries: [(String, Toggle, Selector)] = [
            ("Open at Login", .openAtLogin, #selector(toggleOpenAtLogin)),
            ("New Note Shortcut  ⌃⌥N", .hotKey, #selector(toggleHotKey)),
            ("Pause Syncing", .pauseSync, #selector(togglePauseSync)),
            ("Hide Dock", .hideDock, #selector(toggleHideDock)),
        ]
        for (title, tag, action) in entries {
            if tag == .pauseSync { menu.addItem(.separator()) }
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.tag = tag.rawValue
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        let reveal = NSMenuItem(
            title: "Reveal Database in Finder", action: #selector(revealDatabase), keyEquivalent: ""
        )
        reveal.target = self
        menu.addItem(reveal)

        item.submenu = menu
        return item
    }

    private func aboutItem() -> NSMenuItem {
        let item = NSMenuItem(title: "About StickyDock", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "About")

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let line = NSMenuItem(title: "Version \(version) (\(build))", action: nil, keyEquivalent: "")
        line.isEnabled = false
        menu.addItem(line)

        let updates = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: ""
        )
        updates.target = self
        menu.addItem(updates)

        let source = NSMenuItem(
            title: "Source on GitHub…", action: #selector(openSource), keyEquivalent: ""
        )
        source.target = self
        menu.addItem(source)

        item.submenu = menu
        return item
    }

    private static let releasesURL = "https://github.com/hengkysandy/stickydock/releases"
    private static let sourceURL = "https://github.com/hengkysandy/stickydock"

    // MARK: - Menu actions

    @objc private func newNote() {
        guard let state, let panel else { return }
        let note = state.newNote()
        panel.openEditor(for: note.id)
    }

    @objc private func showAllNotes() {
        allNotes?.show()
    }

    @objc private func bringDesktopNotesToFront() {
        stickyWindows?.bringAllToFront()
    }

    @objc private func syncNow() {
        coordinator?.syncNow()
    }

    // MARK: - Settings

    @objc private func toggleOpenAtLogin() {
        let wanted = !LoginItem.isEnabled
        if let problem = LoginItem.set(wanted) {
            let alert = NSAlert()
            alert.messageText = "Could not change Open at Login"
            alert.informativeText = problem
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func toggleHotKey() {
        Preferences.hotKeyEnabled.toggle()
        hotKey?.unregister()
        hotKey = nil
        setUpHotKey()
    }

    @objc private func togglePauseSync() {
        Preferences.syncPaused.toggle()
        coordinator?.pauseChanged()
    }

    @objc private func toggleHideDock() {
        Preferences.dockHidden.toggle()
        panel?.setHidden(Preferences.dockHidden)
    }

    @objc private func revealDatabase() {
        NSWorkspace.shared.activateFileViewerSelecting([Preferences.databaseURL])
    }

    @objc private func checkForUpdates() {
        if let url = URL(string: Self.releasesURL) { NSWorkspace.shared.open(url) }
    }

    @objc private func openSource() {
        if let url = URL(string: Self.sourceURL) { NSWorkspace.shared.open(url) }
    }

    private func fatalCannotOpenDatabase(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "StickyDock cannot open its notes database"
        alert.informativeText = "\(Preferences.databaseURL.path)\n\n\(error)"
        alert.runModal()
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// The status line is refreshed as the menu opens rather than on a timer,
    /// because nobody can read it while it is closed.
    ///
    /// AppKit calls this on the main thread, but `NSMenu` is not Sendable, so
    /// the compiler will not let it cross into an `assumeIsolated` closure.
    /// Reading `statusItem?.menu` back on the main actor gets to the same menu
    /// without passing it across an isolation boundary.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard let state, let items = statusItem?.menu?.items else { return }
            items.first { $0.tag == Self.statusLineTag }?
                .title = state.syncProblem ?? state.lastSyncSummary
            if let settings = items.first(where: { $0.submenu?.title == "Settings" })?.submenu {
                for entry in settings.items {
                    switch Toggle(rawValue: entry.tag) {
                    case .openAtLogin:
                        entry.state = LoginItem.isEnabled ? .on : .off
                        // The user can switch this off in System Settings, and
                        // the menu should say so rather than show a stale tick.
                        entry.title = LoginItem.deniedByUser
                            ? "Open at Login  (blocked in System Settings)"
                            : "Open at Login"
                    case .hotKey:   entry.state = Preferences.hotKeyEnabled ? .on : .off
                    case .pauseSync: entry.state = Preferences.syncPaused ? .on : .off
                    case .hideDock:  entry.state = Preferences.dockHidden ? .on : .off
                    case .none:      break
                    }
                }
            }
            if let front = items.first(where: { $0.tag == Self.desktopNotesTag }) {
                let count = stickyWindows?.openCount ?? 0
                front.isHidden = count == 0
                front.title = count == 1
                    ? "Bring 1 Desktop Note to Front"
                    : "Bring \(count) Desktop Notes to Front"
            }
        }
    }
}
