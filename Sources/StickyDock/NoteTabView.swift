import AppKit
import SwiftUI
import StickyDockCore

/// One note as a tab hugging the screen edge.
///
/// The label runs vertically along the tab's leading edge, so a whole deck of
/// notes is readable in a strip about 56pt wide. Hover it for a peek, click to
/// open, drag it out to put it on the desktop.
struct NoteTabView: View {
    @EnvironmentObject private var state: AppState
    let note: Note
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hasArrived = false
    /// Where the pointer was when this drag began, in screen coordinates.
    @State private var dragOrigin: NSPoint?

    /// How far sideways before the note comes out onto the desktop.
    private static let pullThreshold: Double = 16
    /// How far up or down before the tab starts changing places. Lower than the
    /// pull threshold, because a reorder is easy to undo and a detach is not.
    private static let liftThreshold: Double = 8

    var body: some View {
        HStack(spacing: 0) {
            labelStrip
            body_
        }
        .frame(width: Theme.tabWidth, height: Theme.tabHeight)
        .background(
            TabShape()
                .fill(Theme.fill(note.color))
                .shadow(color: .black.opacity(isLifted ? 0.34 : (isSelected ? 0.28 : 0.16)),
                        radius: isLifted ? 10 : (isSelected ? 7 : 4), x: -2, y: 1)
        )
        .overlay(TabShape().strokeBorder(.black.opacity(0.07), lineWidth: 1))
        .clipShape(TabShape())
        // Selected and hovered tabs lean out towards the pointer.
        .offset(x: isLifted ? -10 : (isSelected ? -6 : (state.hoveredNoteId == note.id ? -3 : 0)))
        .scaleEffect(isLifted ? 1.04 : 1)
        .opacity(state.draggingNoteId == note.id ? 0.3 : (hasArrived ? 1 : 0))
        .offset(x: hasArrived ? 0 : 26)
        .contentShape(Rectangle())
        // Only an entry is acted on. **An exit is ignored on purpose.** The
        // tracking area lives inside the panel, and AppKit rebuilds it every
        // time the panel resizes, delivering a false "the pointer left" each
        // time. Acting on that cleared the peek, which narrowed the panel, which
        // rebuilt the tracking area, which reported the pointer back inside: the
        // deck flickered between 81 and 154 points wide, about ten times a
        // second, for as long as the pointer rested on a tab. The pointer really
        // leaving is reported by the panel itself, which is a fixed rectangle
        // and does not resize under the pointer.
        .background(HoverReporter { inside in
            if inside { state.hoveredNoteId = note.id }
        })
        .gesture(tapOrDrag)
        .onAppear {
            // Staggered, so the deck shingles open instead of appearing at once.
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)
                .delay(Double(index) * Theme.tabStagger)) {
                hasArrived = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            ConflictCopy.originalTitle(of: note.title).map { "Conflict copy of \($0)" } ?? note.title
        ))
        .accessibilityHint(Text(
            "Open this note, drag it up or down to reorder, or drag it sideways onto the desktop"
        ))
    }

    /// A conflict copy's real title is `<title> (conflict <date>)`, which the
    /// tab cuts back to `<title>`, so the copy looked like a duplicate of the
    /// note it came from. The warning sign goes first so it survives the cut.
    private var label: String {
        if let original = ConflictCopy.originalTitle(of: note.title) {
            return "⚠ " + original.uppercased()
        }
        return note.title.uppercased()
    }

    /// True while this tab is the one being carried up or down the deck.
    private var isLifted: Bool { state.reorderingNoteId == note.id }

    private var labelStrip: some View {
        ZStack {
            Theme.labelStrip(note.color)
            // The frame goes on before the rotation, so a long title truncates
            // along the tab instead of running off both ends of it.
            Text(label)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .kerning(0.7)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.ink.opacity(0.75))
                .frame(width: Theme.tabHeight - 18, alignment: .leading)
                // Reads bottom to top, the way a spine label does.
                .rotationEffect(.degrees(-90))
                .frame(width: Theme.tabLabelWidth, height: Theme.tabHeight - 18)
        }
        .frame(width: Theme.tabLabelWidth)
        .overlay(alignment: .trailing) {
            // The dashed seam between the label and the note.
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 2.5]))
                .foregroundStyle(Theme.ink.opacity(0.22))
                .frame(width: 1)
        }
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(previewLines.indices, id: \.self) { line in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.ink.opacity(0.16))
                    .frame(width: previewLines[line], height: 2.5)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .padding(.top, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Abstract rules standing in for the note's text. At 34pt wide real words
    /// would be unreadable, and pretending otherwise just looks like a bug.
    private var previewLines: [CGFloat] {
        let widths: [CGFloat] = [26, 20, 24, 14]
        let lineCount = min(max(note.text.split(separator: "\n").count, 1), 4)
        return Array(widths.prefix(lineCount))
    }

    /// Click to open, drag up or down to change places, drag sideways to put the
    /// note on the desktop.
    ///
    /// All three are one gesture because a separate `onTapGesture` swallows the
    /// drag. Which of the two drags this is gets decided once, on the first
    /// movement past a threshold, and then never revisited: letting the decision
    /// change mid-drag means a tab that jumps out of the deck halfway through
    /// being reordered.
    ///
    /// The distance is measured against `NSEvent.mouseLocation`, in screen
    /// coordinates, rather than SwiftUI's `translation`. SwiftUI measures
    /// translation inside the window, and this window resizes itself whenever a
    /// peek opens or closes. A drag straight down the screen therefore arrived
    /// here as a sideways jitter of thirty points a frame, which read as a pull
    /// towards the desktop and threw the note out of the deck.
    private var tapOrDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                guard let origin = dragOrigin else {
                    dragOrigin = mouse
                    return
                }
                // Down the screen is positive, matching the deck's own order.
                let along = origin.y - mouse.y
                let sideways = mouse.x - origin.x

                if state.reorderingNoteId == note.id {
                    state.updateReorder(note.id, verticalDrag: along)
                    return
                }
                guard state.draggingNoteId == nil, state.reorderingNoteId == nil else { return }
                if abs(along) > Self.liftThreshold, abs(along) > abs(sideways) {
                    state.beginReorder(note.id)
                    state.updateReorder(note.id, verticalDrag: along)
                } else if abs(sideways) > Self.pullThreshold {
                    state.detachByDragging(note.id, from: NotePoint(x: mouse.x, y: mouse.y))
                }
            }
            .onEnded { _ in
                let origin = dragOrigin
                dragOrigin = nil
                if state.reorderingNoteId == note.id {
                    state.endReorder()
                    return
                }
                guard state.draggingNoteId == nil else { return }
                let mouse = NSEvent.mouseLocation
                let travelled = origin.map {
                    max(abs(mouse.x - $0.x), abs(mouse.y - $0.y))
                } ?? 0
                if travelled <= Self.pullThreshold { onTap() }
            }
    }
}

/// A tab rounded on its leading edge and square against the screen edge.
struct TabShape: InsettableShape {
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> TabShape {
        TabShape(inset: inset + amount)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let radius = min(11, r.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.minY))
        path.addQuadCurve(
            to: CGPoint(x: r.minX, y: r.minY + radius),
            control: CGPoint(x: r.minX, y: r.minY)
        )
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: r.minX + radius, y: r.maxY),
            control: CGPoint(x: r.minX, y: r.maxY)
        )
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        path.closeSubpath()
        return path
    }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 6))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 6))
        return path
    }
}
