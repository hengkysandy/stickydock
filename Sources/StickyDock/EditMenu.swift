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
@MainActor
enum EditMenu {

    /// Bold, italic and underline. The actions target `nil` so AppKit sends them
    /// to the first responder, which is the note's text view.
    private static func formatItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Format")
        let entries: [(String, Selector, String)] = [
            ("Bold", #selector(NoteTextView.toggleBold(_:)), "b"),
            ("Italic", #selector(NoteTextView.toggleItalic(_:)), "i"),
            ("Underline", #selector(NoteTextView.toggleUnderlineStyle(_:)), "u"),
        ]
        for (title, action, key) in entries {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = [.command]
            menu.addItem(entry)
        }
        item.submenu = menu
        return item
    }

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
        // The system find bar, on the standard shortcut. NSTextView provides the
        // whole interface; it just has to be asked for it through a menu item,
        // because that is how AppKit routes ⌘F.
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        let findSubmenu = NSMenu(title: "Find")
        let findEntries: [(String, Int, String, NSEvent.ModifierFlags)] = [
            ("Find…", NSTextFinder.Action.showFindInterface.rawValue, "f", [.command]),
            ("Find Next", NSTextFinder.Action.nextMatch.rawValue, "g", [.command]),
            ("Find Previous", NSTextFinder.Action.previousMatch.rawValue, "g", [.command, .shift]),
            ("Use Selection for Find", NSTextFinder.Action.setSearchString.rawValue, "e", [.command]),
            ("Hide Find Bar", NSTextFinder.Action.hideFindInterface.rawValue, "", []),
        ]
        for (title, tag, key, modifiers) in findEntries {
            let item = NSMenuItem(
                title: title,
                action: #selector(NSTextView.performTextFinderAction(_:)),
                keyEquivalent: key
            )
            item.tag = tag
            item.keyEquivalentModifierMask = modifiers
            findSubmenu.addItem(item)
        }
        find.submenu = findSubmenu
        edit.addItem(find)

        editItem.submenu = edit
        main.addItem(editItem)
        main.addItem(formatItem())

        NSApp.mainMenu = main
    }
}
