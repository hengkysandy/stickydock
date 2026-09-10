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

    private static let pullThreshold: Double = 16

    var body: some View {
        HStack(spacing: 0) {
            labelStrip
            body_
        }
        .frame(width: Theme.tabWidth, height: Theme.tabHeight)
        .background(
            TabShape()
                .fill(Theme.fill(note.color))
                .shadow(color: .black.opacity(isSelected ? 0.28 : 0.16),
                        radius: isSelected ? 7 : 4, x: -2, y: 1)
        )
        .overlay(TabShape().strokeBorder(.black.opacity(0.07), lineWidth: 1))
        .clipShape(TabShape())
        // Selected and hovered tabs lean out towards the pointer.
        .offset(x: isSelected ? -6 : (state.hoveredNoteId == note.id ? -3 : 0))
        .opacity(state.draggingNoteId == note.id ? 0.3 : (hasArrived ? 1 : 0))
        .offset(x: hasArrived ? 0 : 26)
        .contentShape(Rectangle())
        .background(HoverReporter { inside in
            if inside {
                state.hoveredNoteId = note.id
            } else if state.hoveredNoteId == note.id {
                state.hoveredNoteId = nil
            }
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
        .accessibilityLabel(Text(note.title))
        .accessibilityHint(Text("Open this note, or drag it onto the desktop"))
    }

    private var labelStrip: some View {
        ZStack {
            Theme.labelStrip(note.color)
            // The frame goes on before the rotation, so a long title truncates
            // along the tab instead of running off both ends of it.
            Text(note.title.uppercased())
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

    private var tapOrDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let travelled = max(abs(value.translation.width), abs(value.translation.height))
                guard travelled > Self.pullThreshold, state.draggingNoteId == nil else { return }
                let mouse = NSEvent.mouseLocation
                state.detachByDragging(note.id, from: NotePoint(x: mouse.x, y: mouse.y))
            }
            .onEnded { value in
                let travelled = max(abs(value.translation.width), abs(value.translation.height))
                if travelled <= Self.pullThreshold, state.draggingNoteId == nil {
                    onTap()
                }
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
