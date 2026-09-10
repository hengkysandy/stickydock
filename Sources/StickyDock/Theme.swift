import AppKit
import SwiftUI
import StickyDockCore

/// The one place colours are defined, so the dot on the edge and the card behind
/// the text can never drift apart.
enum Theme {
    static func fill(_ color: NoteColor) -> Color {
        switch color {
        case .yellow: Color(red: 1.00, green: 0.85, blue: 0.35)
        case .pink:   Color(red: 1.00, green: 0.62, blue: 0.72)
        case .blue:   Color(red: 0.53, green: 0.78, blue: 0.98)
        case .green:  Color(red: 0.60, green: 0.87, blue: 0.60)
        case .purple: Color(red: 0.76, green: 0.68, blue: 0.98)
        case .grey:   Color(red: 0.80, green: 0.82, blue: 0.85)
        }
    }

    /// Every note colour is a light pastel, so the text on top is always dark.
    /// Fixed rather than semantic on purpose: the card keeps its colour in dark
    /// mode, so a colour that follows the system theme would go invisible.
    static let ink = Color(red: 0.13, green: 0.13, blue: 0.15)
    /// The same ink, for the AppKit text view.
    static let inkNS = NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    static let inkSoft = Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.55)

    static let cardRadius: CGFloat = 10
    static let collapsedWidth: CGFloat = 14

    /// The fanned deck is a column of tabs hugging the screen edge. It stays
    /// narrow: the tabs are a way in, not the content.
    static let tabWidth: CGFloat = 56
    static let tabHeight: CGFloat = 82
    static let tabLabelWidth: CGFloat = 17
    static let tabOverlap: CGFloat = 6
    /// Each tab arrives a beat after the one above it.
    static let tabStagger: Double = 0.045

    static let peekWidth: CGFloat = 236
    static let editorWidth: CGFloat = 330
    static let panelHeight: CGFloat = 470

    /// A slightly deeper version of the note colour, for the tab's label strip.
    static func labelStrip(_ color: NoteColor) -> Color {
        fill(color).opacity(0.72)
    }
}
