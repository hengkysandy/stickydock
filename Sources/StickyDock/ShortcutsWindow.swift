import AppKit
import SwiftUI
import StickyDockCore

struct ShortcutsView: View {
    /// Bumped on every edit so the rows redraw. `Preferences` is the store, not
    /// this view, so there is nothing else to observe.
    @State private var revision = 0
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 2)
            Text("Click a shortcut, then press the keys. Delete clears it, Escape leaves it alone.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            Divider()

            ForEach(ShortcutAction.allCases) { action in
                row(for: action)
                if action != ShortcutAction.allCases.last { Divider().padding(.leading, 16) }
            }

            Divider()
            HStack {
                Button("Restore Defaults") {
                    for action in ShortcutAction.allCases { Preferences.resetShortcut(for: action) }
                    bump()
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 460)
    }

    private func row(for action: ShortcutAction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(action.title).font(.system(size: 12, weight: .medium))
                // Wraps rather than truncates. A description cut off at "or le…"
                // is worse than no description at all.
                Text(action.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ShortcutRecorder(combo: Preferences.shortcut(for: action)) { combo in
                Preferences.setShortcut(combo, for: action)
                bump()
            }
            .frame(width: 132, height: 24)
            .id(revision)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func bump() {
        revision += 1
        onChange()
    }
}

/// Holds the single Shortcuts window.
@MainActor
final class ShortcutsWindow {
    private var window: NSWindow?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        created.title = "Shortcuts"
        created.isReleasedWhenClosed = false
        created.contentView = NSHostingView(rootView: ShortcutsView(onChange: onChange))
        created.setContentSize(created.contentView?.fittingSize ?? created.frame.size)
        created.center()
        window = created
        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}
