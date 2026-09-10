import AppKit
import SwiftUI
import StickyDockCore

/// One note as a card in the fanned deck.
///
/// Tap opens it in the dock editor. Drag it out and it becomes a real window on
/// the desktop that follows the pointer until the mouse comes up.
struct NoteCardView: View {
    @EnvironmentObject private var state: AppState
    let note: Note
    let isTop: Bool
    let onTap: () -> Void

    private static let pullThreshold: Double = 16

    var body: some View {
        card
            .contentShape(Rectangle())
            .opacity(state.draggingNoteId == note.id ? 0.3 : 1)
            .gesture(tapOrDrag)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(note.title))
            .accessibilityHint(Text("Open this note, or drag it onto the desktop"))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Theme.ink)
            Text(preview)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.fill(note.color))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isTop ? 0.20 : 0.10), radius: isTop ? 6 : 3, y: 2)
    }

    /// Tap to open, drag to pull the note onto the desktop.
    ///
    /// One gesture handles both. Using a separate `.onTapGesture` alongside a
    /// `DragGesture` looks tidier and does not work: the tap claims the event
    /// sequence first and the drag never fires at all. A single `DragGesture`
    /// with `minimumDistance: 0` sees every press, and the distance travelled by
    /// the time the mouse comes up says which one the user meant.
    ///
    /// The threshold stops a slightly sloppy click from flinging a note onto the
    /// desktop. Once crossed, the window is created straight away and then
    /// follows `NSEvent.mouseLocation` rather than the gesture's own translation,
    /// because the pointer leaves the dock panel immediately and screen
    /// coordinates are the only frame of reference that stays true.
    private var tapOrDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let travelled = max(abs(value.translation.width), abs(value.translation.height))
                guard travelled > Self.pullThreshold, state.draggingNoteId == nil else { return }
                // This does not return until the mouse comes up.
                state.detachByDragging(note.id, from: Self.pointerLocation())
            }
            .onEnded { value in
                let travelled = max(abs(value.translation.width), abs(value.translation.height))
                if travelled <= Self.pullThreshold, state.draggingNoteId == nil {
                    onTap()
                }
            }
    }

    /// Screen coordinates, bottom-left origin, which is what `NSWindow` wants.
    private static func pointerLocation() -> NotePoint {
        let mouse = NSEvent.mouseLocation
        return NotePoint(x: Double(mouse.x), y: Double(mouse.y))
    }

    /// The body without the title line, since the title is already shown above.
    private var preview: String {
        let rest = note.text.components(separatedBy: "\n").dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? "No other text" : rest
    }
}
