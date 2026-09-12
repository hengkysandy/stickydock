import Foundation
import StickyDockCore

/// The things a global shortcut can do.
///
/// Each one is optional: no shortcut set means no hot key registered, which is
/// the right default for everything except making a note.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case newNote
    case toggleNotesOnTop
    case toggleDock
    case togglePauseSync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newNote:          "New Note"
        case .toggleNotesOnTop: "Keep Desktop Notes on Top"
        case .toggleDock:       "Hide or Show the Dock"
        case .togglePauseSync:  "Pause or Resume Syncing"
        }
    }

    var detail: String {
        switch self {
        case .newNote:          "Creates a note and opens it, from any app."
        case .toggleNotesOnTop: "Flips desktop notes between floating and ordinary."
        case .toggleDock:       "Hides the edge dock, or brings it back."
        case .togglePauseSync:  "Holds off talking to Apple Notes, or resumes."
        }
    }

    /// Only New Note ships with one. Binding several by default would take keys
    /// out of the user's hands that they never asked us to have.
    var factoryDefault: KeyCombo? {
        switch self {
        case .newNote: KeyCombo(keyCode: 45, modifiers: KeyCombo.control | KeyCombo.option)
        default: nil
        }
    }
}
