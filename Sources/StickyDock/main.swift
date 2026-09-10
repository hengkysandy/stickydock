import AppKit

// An executable target with a main.swift cannot also use @main, so the app is
// bootstrapped by hand. .accessory matches LSUIElement: no Dock icon, no menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
