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
        panel.orderFront(nil)

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

        EditMenu.install()
        setUpSync(state: state, store: store)
        setUpStatusItem()
        setUpHotKey()

        allNotes = AllNotesWindow(state: state) { [weak self] note in
            self?.panel?.openEditor(for: note.id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The editor debounces writes by 400ms. Quitting mid-sentence must not
        // drop the last thing typed.
        state?.flushPendingEdit()
        coordinator?.stop()
        hotKey?.unregister()
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
        let quit = NSMenuItem(
            title: "Quit StickyDock",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        menu.addItem(quit)
        return menu
    }

    private static let statusLineTag = 991

    // MARK: - Menu actions

    @objc private func newNote() {
        guard let state, let panel else { return }
        let note = state.newNote()
        panel.openEditor(for: note.id)
    }

    @objc private func showAllNotes() {
        allNotes?.show()
    }

    @objc private func syncNow() {
        coordinator?.syncNow()
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
            guard let state,
                  let line = statusItem?.menu?.items.first(where: { $0.tag == Self.statusLineTag })
            else { return }
            line.title = state.syncProblem ?? state.lastSyncSummary
        }
    }
}
