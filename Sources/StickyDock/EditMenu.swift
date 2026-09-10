import AppKit

/// Installs the standard Edit menu.
///
/// This is not cosmetic. `LSUIElement` apps have no visible menu bar, and it is
/// tempting to skip building a main menu at all. Doing that silently kills every
/// standard keyboard command inside the app: Cut, Copy, Paste, Undo and Select
/// All all stop working, because AppKit routes those key equivalents through
/// menu items. A note editor where Cmd+V does nothing is broken.
///
/// The items target `nil`, so AppKit sends them to whatever holds first
/// responder, which is the note's text view.
enum EditMenu {
    static func install() {
        let main = NSMenu()

        // AppKit expects the first top-level item to be the application menu,
        // even when nothing is drawn on screen.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit StickyDock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        let entries: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", [.command]),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", [.command]),
            ("Copy", #selector(NSText.copy(_:)), "c", [.command]),
            ("Paste", #selector(NSText.paste(_:)), "v", [.command]),
            ("Select All", #selector(NSText.selectAll(_:)), "a", [.command]),
        ]
        for (title, action, key, modifiers) in entries {
            if title == "Redo" { edit.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
