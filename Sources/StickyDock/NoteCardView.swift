import SwiftUI
import StickyDockCore

/// One note as a card in the fanned deck.
struct NoteCardView: View {
    let note: Note
    let isTop: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
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
        .buttonStyle(.plain)
        .accessibilityLabel(Text(note.title))
        .accessibilityHint(Text("Open this note"))
    }

    /// The body without the title line, since the title is already shown above.
    private var preview: String {
        let lines = note.text.components(separatedBy: "\n")
        let rest = lines.dropFirst().joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? "No other text" : rest
    }
}
