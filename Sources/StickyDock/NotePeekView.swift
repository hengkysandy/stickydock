import SwiftUI
import StickyDockCore

/// The sneak peek shown while the pointer rests on a tab.
///
/// Read-only on purpose. It appears from a hover, and a hover is not a decision:
/// anything editable here would be one stray mouse movement away from being
/// changed by accident. Clicking the tab opens the real editor.
struct NotePeekView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(Theme.ink)

            Text(bodyPreview)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .lineLimit(10)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Theme.ink.opacity(0.75))

            Text("Click to edit  ·  drag to the desktop")
                .font(.system(size: 9))
                .foregroundStyle(Theme.ink.opacity(0.45))
        }
        .padding(12)
        // Height follows the text. A card stretched to the full panel height
        // would put the hint line miles away from the note it belongs to.
        .frame(width: Theme.peekWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.fill(note.color))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, x: -4, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Preview of \(note.title)"))
    }

    private var bodyPreview: String {
        let rest = note.text.components(separatedBy: "\n").dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? "Nothing else in this note yet." : rest
    }
}
